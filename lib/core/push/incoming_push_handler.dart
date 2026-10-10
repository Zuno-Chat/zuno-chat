import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../calls/active_call_marker.dart';
import '../calls/matrixrtc/call_summary_message.dart';
import '../calls/matrixrtc/incoming_call.dart';
import '../calls/matrixrtc/incoming_call_provider.dart';
import '../calls/matrixrtc/resolved_call_ids_store.dart';
import '../calls/notifications/call_notification_service.dart';
import '../calls/notifications/ring_notification.dart';
import '../calls/notifications/ringing_call_store.dart';
import '../calls/platform/incoming_call_presenter.dart';
import '../calls/platform/system_ring.dart';
import '../matrix/room_title.dart';
import '../matrix/undecryptable_event.dart';
import '../matrix/zuno_client.dart';
import '../notifications/invite_notification_provider.dart';
import '../notifications/message_notification_image.dart';
import '../notifications/message_notification_poster.dart';
import '../notifications/message_notification_provider.dart';
import '../notifications/notify_me.dart';
import '../notifications/verification_request_notification.dart';
import '../platform/platform_capabilities.dart';
import 'push_timing.dart';

const defaultPlaceholderAfter = Duration(seconds: 3);
const messageCatchUpWait = Duration(milliseconds: 1500);
const _noticeReplacedWithin = Duration(seconds: 30);

Future<bool> _readSince(Client client, Event event) async {
  final room = client.getRoomById(event.room.id) ?? event.room;
  final fullyRead = room.fullyRead;
  if (fullyRead.isEmpty) return false;
  if (fullyRead == event.eventId) return true;
  try {
    final marker = await client.database.getEventById(fullyRead, room);
    return marker != null &&
        marker.originServerTs.isAfter(event.originServerTs);
  } catch (_) {
    return false;
  }
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
      : CallNotificationService.instance.expectPushNotice(roomId, eventId);
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
  final placeholder = _Placeholder(
    client,
    notification,
    quiet: notifyMe == NotifyMe.mentionsOnly,
  );
  final catchUp = client is ZunoClient
      ? client.syncCoordinator?.catchUp()
      : null;
  final Event? event;
  try {
    event = await placeholder.race(
      () => client.getEventByPushNotification(
        notification,
        storeInDatabase: catchUp == null && !client.syncPending,
      ),
      after: placeholderAfter,
    );
  } catch (e) {
    timing?.mark('fetch-failed');
    debugPrint('zuno/push: could not fetch the event for this push: $e');
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
    final callId = event.content.tryGet<String>('call_id');
    if (callId != null) await markCallResolved(callId);
    final ringAge = callId == null ? null : await _ringAge(callId);
    if (ringAge != null && ringAge < _ringSummaryGrace) {
      await Future<void>.delayed(_ringSummaryGrace - ringAge);
    }
    await ring.cancelIncoming(roomId: event.room.id, callId: callId);
    if (!isMissedCallSummary(event)) {
      await placeholder.retract();
      return IncomingPushOutcome.ignored;
    }
  }

  final call = incomingCallFromEvent(client, event);
  if (call != null) {
    final outcome = await _ring(call, ring);
    await placeholder.retract();
    return outcome;
  }

  final invite = inviteNotificationFor(client, event);
  if (invite != null) {
    final claim = await claimInviteAnnouncement(invite.roomId);
    if (!claim.won) {
      debugPrint('zuno/push: invitation to ${invite.roomId} already shown');
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
        includeMessageActions: false,
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
      includeMessageActions: false,
      onRefining: onRefining,
    );
    await placeholder.retract();
    return IncomingPushOutcome.message;
  }

  if (catchUp != null &&
      await placeholder.caughtUp(catchUp) &&
      await _readSince(client, event)) {
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
    fetchImage: () => fetchMessageNotificationImage(resolved),
    onPosted: () => timing?.mark('post'),
    onRefining: onRefining,
    timing: timing,
  );
  timing?.mark('refine');
  return IncomingPushOutcome.message;
}

class _Placeholder {
  _Placeholder(this.client, this.notification, {required this.quiet});

  final Client client;
  final PushNotification notification;
  final bool quiet;
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
    if (!settled.isCompleted) await post();
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
    final content = unresolvedPushNotification(
      client,
      notification,
      quiet: quiet,
    );
    if (content == null) return false;
    _posted = true;
    debugPrint('zuno/push: showing a placeholder while the fetch continues');
    await postMessageNotification(content, client: client, placeholder: true);
    return true;
  }

  Future<void> retract() =>
      _settle(CallNotificationService.instance.retractPushNotice);

  Future<void> settleAfterAnnounced({required bool replacedNotice}) {
    if (!replacedNotice) return retract();
    return _settle(CallNotificationService.instance.takePushNotice);
  }

  Future<void> _settle(
    Future<void> Function(String roomId, String eventId) settleNotice,
  ) async {
    final roomId = notification.roomId;
    final eventId = notification.eventId;
    if (roomId == null || eventId == null) return;
    await settleNotice(roomId, eventId);
    if (!_posted) return;
    await CallNotificationService.instance.retractPlaceholder(roomId, eventId);
  }
}

Future<IncomingPushOutcome> _ring(
  IncomingCall call,
  IncomingCallPresenter ring,
) async {
  final callId = call.callId;
  if (isCallActiveInProcess()) {
    if (kDebugMode) {
      debugPrint('zuno/push: already on a call, not ringing $callId');
    }
    return IncomingPushOutcome.ignored;
  }
  if (await isCallResolved(callId)) {
    if (kDebugMode) {
      debugPrint('zuno/push: $callId already resolved, not ringing');
    }
    return IncomingPushOutcome.ignored;
  }
  final heldHere = await _whileRinging(
    SystemRing.instance.ringing.value?.callId,
    callId,
  );
  if (heldHere != null) return heldHere;
  final ringingNow = ring.activeRing();
  final busy = await _whileRinging((await ringingNow)?.callId, callId);
  if (busy != null) return busy;
  SystemRing.instance.set(roomId: call.room.id, callId: callId);
  var outcome = RingOutcome.unavailable;
  try {
    outcome = await postRingNotification(
      call,
      presenter: ring,
      ringingNow: ringingNow,
    );
  } finally {
    if (outcome != RingOutcome.shown) SystemRing.instance.clear(callId);
  }
  if (outcome != RingOutcome.shown) return IncomingPushOutcome.ignored;
  if (kDebugMode) {
    debugPrint('zuno/push: ring notification posted for $callId');
  }
  return IncomingPushOutcome.callRinging;
}

Future<IncomingPushOutcome?> _whileRinging(
  String? ringing,
  String callId,
) async {
  if (ringing == null) return null;
  if (ringing == callId) {
    if (kDebugMode) debugPrint('zuno/push: $callId already rings');
    return IncomingPushOutcome.callRinging;
  }
  if (await isCallResolved(ringing)) return null;
  if (kDebugMode) {
    debugPrint('zuno/push: $ringing is ringing, not ringing $callId');
  }
  return IncomingPushOutcome.ignored;
}

const _ringSummaryGrace = Duration(seconds: 3);

Future<Duration?> _ringAge(String callId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return ringAgeFor(prefs, callId);
  } catch (_) {
    return null;
  }
}

MessageNotificationContent? unresolvedPushNotification(
  Client client,
  PushNotification notification, {
  bool quiet = false,
}) {
  final roomId = notification.roomId;
  if (roomId == null) return null;
  final room = client.getRoomById(roomId);
  final localName = room == null ? null : roomTitle(room).trim().nullIfEmpty;
  final name = notification.roomName?.trim().nullIfEmpty;
  final sender = notification.senderDisplayName?.trim().nullIfEmpty;
  final title = name ?? localName ?? sender ?? 'New message';
  return MessageNotificationContent(
    roomId: roomId,
    title: title,
    body: 'Tap to open',
    text: 'New message',
    eventId: notification.eventId,
    isDirectChat: room?.isDirectChat ?? true,
    senderName: title,
    quiet: quiet,
  );
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

enum IncomingPushOutcome { ignored, message, callRinging, badge }
