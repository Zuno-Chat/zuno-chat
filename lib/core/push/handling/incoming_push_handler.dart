import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:matrix/matrix.dart';

import '../../calls/matrixrtc/call_summary_message.dart';
import '../../calls/matrixrtc/incoming_call_provider.dart';
import '../../calls/notifications/ring_from_push.dart';
import '../../calls/platform/incoming_call_presenter.dart';
import '../../errors/caught_errors.dart';
import '../../matrix/room_title.dart';
import '../../matrix/undecryptable_event.dart';
import '../../matrix/zuno_client.dart';
import '../../notifications/messages/message_notification_image.dart';
import '../../notifications/messages/message_notification_poster.dart';
import '../../notifications/messages/message_notification_provider.dart';
import '../../notifications/messages/message_notifications.dart';
import '../../notifications/room_invite_notification_provider.dart';
import '../../notifications/settings/notification_preview.dart';
import '../../notifications/settings/notify_me.dart';
import '../../notifications/verification_request_notification.dart';
import '../../platform/platform_capabilities.dart';
import 'push_timing.dart';

const defaultPlaceholderAfter = Duration(seconds: 3);
const messageCatchUpWait = Duration(milliseconds: 1500);
const _noticeReplacedWithin = Duration(seconds: 30);

bool _readElsewhere(Client client, Event event) {
  final room = client.getRoomById(event.room.id) ?? event.room;
  if (room.notificationCount > 0) return false;
  final last = room.lastEvent;
  return last != null &&
      (last.eventId == event.eventId ||
          !last.originServerTs.isBefore(event.originServerTs));
}

Future<IncomingPushOutcome> handleIncomingPushNotification(
  Client client,
  PushNotification notification, {
  required NotifyMe notifyMe,
  String? currentlyOpenRoomId,
  Duration placeholderAfter = defaultPlaceholderAfter,
  PushTiming? timing,
  IncomingCallPresenter? incomingCallPresenter,
  void Function(Future<void> refinement)? onRefining,
}) async {
  final roomId = notification.roomId;
  final eventId = notification.eventId;
  final forgetNotice = roomId == null || eventId == null
      ? null
      : MessageNotifications.instance.expectPushNotice(roomId, eventId);
  try {
    return await _handle(
      client,
      notification,
      notifyMe: notifyMe,
      currentlyOpenRoomId: currentlyOpenRoomId,
      placeholderAfter: placeholderAfter,
      timing: timing,
      ring:
          incomingCallPresenter ??
          incomingCallPresenterFor(ambientCapabilities),
      onRefining: onRefining,
    );
  } finally {
    forgetNotice?.call();
  }
}

Future<IncomingPushOutcome> _handle(
  Client client,
  PushNotification notification, {
  required NotifyMe notifyMe,
  required String? currentlyOpenRoomId,
  required Duration placeholderAfter,
  required PushTiming? timing,
  required IncomingCallPresenter ring,
  required void Function(Future<void> refinement)? onRefining,
}) async {
  final handlingSince = DateTime.now();
  if (kDebugMode) {
    debugPrint('zuno/push: resolving event ${notification.eventId}');
  }
  final preview = currentNotificationPreview();
  final placeholder = _Placeholder(
    client,
    notification,
    quiet: notifyMe == NotifyMe.mentionsOnly,
    preview: preview,
  );
  final catchUp = client is ZunoClient
      ? client.syncCoordinator?.catchUp()
      : null;
  // shortcut: firstSyncReceived also waits on device keys and to-device work, so a slow tail outlasts messageCatchUpWait and skips read-elsewhere, upgrade by counting the sync as landed at SyncStatus.cleaningUp
  final synced =
      catchUp ?? client.firstSyncReceived?.then<void>((_) {}, onError: (_) {});
  final Event? event;
  try {
    event = await placeholder.race(
      () => reportFailureOf(
        client.getEventByPushNotification(
          notification,
          storeInDatabase: catchUp == null && !client.syncPending,
        ),
        label: 'push event fetch',
      ),
      after: placeholderAfter,
    );
  } catch (_) {
    timing?.mark('fetch-failed');
    return await placeholder.post()
        ? IncomingPushOutcome.message
        : IncomingPushOutcome.ignored;
  }
  timing?.mark('fetch');
  if (event == null) {
    debugPrint('zuno/push: event could not be resolved');
    await placeholder.retract();
    return IncomingPushOutcome.ignored;
  }
  if (isUndecryptableEvent(event)) {
    if (event.senderId == client.userID) {
      await placeholder.retract();
      return IncomingPushOutcome.ignored;
    }
    debugPrint('zuno/push: event did not decrypt, keeping "New message"');
    return await placeholder.post()
        ? IncomingPushOutcome.message
        : IncomingPushOutcome.ignored;
  }
  if (kDebugMode) {
    final age = DateTime.now().difference(event.originServerTs);
    debugPrint(
      'zuno/push: resolved ${event.type}/${event.messageType} '
      'in ${event.room.id}, sent ${age.inSeconds}s ago',
    );
  }

  if (isCallSummaryMessage(event.messageType)) {
    await endRingForCallSummary(event, ring);
    if (!isMissedCallSummary(event)) {
      await placeholder.retract();
      return IncomingPushOutcome.ignored;
    }
  }

  final call = incomingCallFromEvent(client, event);
  if (call != null) {
    final ringing = await ringFromPush(call, ring);
    await placeholder.retract();
    return ringing
        ? IncomingPushOutcome.callRinging
        : IncomingPushOutcome.ignored;
  }

  final invite = inviteNotificationFor(client, event);
  if (invite != null) {
    final claim = await claimInviteAnnouncement(
      invite.roomId,
      userId: client.userID,
    );
    if (!claim.won) {
      debugPrint(
        'zuno/push: invitation to ${invite.roomId} not announced here',
      );
      final announcedAt = claim.announcedAt;
      await placeholder.settleAfterAnnounced(
        replacedNotice:
            announcedAt != null &&
            announcedAt.isAfter(handlingSince.subtract(_noticeReplacedWithin)),
      );
      return IncomingPushOutcome.ignored;
    }
    try {
      await postMessageNotification(
        invite,
        client: client,
        preview: await preview,
        isMessage: false,
        onRefining: onRefining,
      );
    } catch (_) {
      await forgetInviteAnnouncements([invite.roomId]);
      rethrow;
    }
    await placeholder.retract();
    return IncomingPushOutcome.message;
  }

  final verification = verificationRequestNotificationFor(client, event);
  if (verification != null) {
    await postMessageNotification(
      verification,
      client: client,
      preview: await preview,
      isMessage: false,
      onRefining: onRefining,
    );
    await placeholder.retract();
    return IncomingPushOutcome.message;
  }

  if (synced != null &&
      await placeholder.caughtUp(synced) &&
      _readElsewhere(client, event)) {
    debugPrint('zuno/push: read on another device, as the catch-up showed');
    await placeholder.retract();
    return IncomingPushOutcome.ignored;
  }

  final decision = messageNotificationFor(
    client,
    event,
    pushRuleAction: client.pushruleEvaluator.match(event),
    notifyMe: notifyMe,
    currentlyOpenRoomId: currentlyOpenRoomId,
    preview: await preview,
  );
  final content = decision.content;
  if (content == null) {
    if (kDebugMode) {
      debugPrint('zuno/push: not notifying (${decision.refusal?.label})');
    }
    await placeholder.retract();
    return IncomingPushOutcome.ignored;
  }
  final resolved = event;
  await postMessageNotification(
    content,
    client: client,
    preview: await preview,
    fetchImage: () => fetchMessageNotificationImage(resolved),
    onPosted: () => timing?.mark('post'),
    onRefining: onRefining,
    timing: timing,
  );
  timing?.mark('refine');
  return IncomingPushOutcome.message;
}

class _Placeholder {
  _Placeholder(
    this.client,
    this.notification, {
    required this.quiet,
    required this.preview,
  });

  final Client client;
  final PushNotification notification;
  final bool quiet;
  final Future<NotificationPreview> preview;
  bool _posted = false;
  Future<void>? _mark;

  Future<Event?> race(
    Future<Event?> Function() resolve, {
    required Duration after,
  }) async {
    final resolution = resolve();
    final mark = _mark = Future<void>.delayed(after);
    final settled = Completer<void>();
    unawaited(
      resolution.then((_) {}, onError: (_) {}).whenComplete(settled.complete),
    );
    await Future.any([settled.future, mark]);
    if (!settled.isCompleted) {
      await reportFailureOf(post(), label: 'push placeholder post');
    }
    return resolution;
  }

  Future<bool> caughtUp(Future<void> catchUp) async {
    var landed = false;
    final mark = _mark;
    await Future.any([
      catchUp.then((_) => landed = true),
      Future<void>.delayed(messageCatchUpWait),
      if (!_posted && mark != null) mark,
    ]);
    return landed;
  }

  Future<bool> post() async {
    if (_posted) return true;
    if (notification.roomId case final roomId?) {
      if (client.getRoomById(roomId) case final room?) {
        await loadRoomNameMembers(room);
      }
    }
    if (_posted) return true;
    final content = unresolvedPushNotification(
      client,
      notification,
      quiet: quiet,
    );
    if (content == null) return false;
    _posted = true;
    debugPrint('zuno/push: showing a placeholder while the fetch continues');
    await postMessageNotification(
      content,
      client: client,
      preview: await preview,
      placeholder: true,
    );
    return true;
  }

  Future<void> retract() =>
      _settle(MessageNotifications.instance.retractPushNotice);

  Future<void> settleAfterAnnounced({required bool replacedNotice}) {
    if (!replacedNotice) return retract();
    return _settle(MessageNotifications.instance.takePushNotice);
  }

  Future<void> _settle(
    Future<void> Function(String roomId, String eventId) settleNotice,
  ) async {
    final roomId = notification.roomId;
    final eventId = notification.eventId;
    if (roomId == null || eventId == null) return;
    await settleNotice(roomId, eventId);
    if (!_posted) return;
    await MessageNotifications.instance.retractPlaceholder(
      roomId,
      eventId,
      preview: await preview,
    );
  }
}

MessageNotificationContent? unresolvedPushNotification(
  Client client,
  PushNotification notification, {
  bool quiet = false,
}) {
  final roomId = notification.roomId;
  if (roomId == null) return null;
  return messageFloor(
    roomId,
    room: client.getRoomById(roomId),
    eventId: notification.eventId,
    roomName: notification.roomName,
    senderName: notification.senderDisplayName,
    quiet: quiet,
  );
}

enum IncomingPushOutcome { ignored, message, callRinging, badge }
