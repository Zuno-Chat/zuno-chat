import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../calls/matrixrtc/call_summary_message.dart';
import '../calls/matrixrtc/incoming_call_provider.dart';
import '../calls/matrixrtc/resolved_call_ids_store.dart';
import '../calls/notifications/call_notification_service.dart';
import '../calls/notifications/ring_notification.dart';
import '../calls/notifications/ringing_call_store.dart';
import '../matrix/room_title.dart';
import '../notifications/invite_notification_provider.dart';
import '../notifications/message_notification_image.dart';
import '../notifications/message_notification_poster.dart';
import '../notifications/message_notification_provider.dart';
import '../notifications/notify_me.dart';
import 'push_timing.dart';

const defaultPlaceholderAfter = Duration(seconds: 3);

Future<IncomingPushOutcome> handleIncomingPushNotification(
  Client client,
  PushNotification notification, {
  required NotifyMe notifyMe,
  String? currentlyOpenRoomId,
  Duration placeholderAfter = defaultPlaceholderAfter,
  PushTiming? timing,
}) async {
  if (kDebugMode) {
    debugPrint('zuno/push: resolving event ${notification.eventId}');
  }
  final placeholder = _Placeholder(client, notification);
  final Event? event;
  try {
    event = await placeholder.race(
      () => client.getEventByPushNotification(notification),
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
  if (kDebugMode) {
    debugPrint(
      'zuno/push: resolved ${event.type}/${event.messageType} '
      'in ${event.room.id}',
    );
  }

  if (isCallSummaryMessage(event.messageType)) {
    final callId = event.content.tryGet<String>('call_id');
    final ringAge = callId == null ? null : await _ringAge(callId);
    if (ringAge != null && ringAge < _ringSummaryGrace) {
      await Future<void>.delayed(_ringSummaryGrace - ringAge);
    }
    await CallNotificationService.instance.cancelIncomingCall();
    if (callId != null) await _markResolved(callId);
    if (!isMissedCallSummary(event)) {
      await placeholder.retract();
      return IncomingPushOutcome.ignored;
    }
  }

  final call = incomingCallFromEvent(client, event);
  if (call != null) {
    await placeholder.retract();
    if (await _isResolved(call.callId)) {
      if (kDebugMode) {
        debugPrint('zuno/push: ${call.callId} already resolved, not ringing');
      }
      return IncomingPushOutcome.ignored;
    }
    await postRingNotification(call);
    if (kDebugMode) {
      debugPrint('zuno/push: ring notification posted for ${call.callId}');
    }
    return IncomingPushOutcome.callRinging;
  }

  final invite = inviteNotificationFor(client, event);
  if (invite != null) {
    await postMessageNotification(
      invite,
      client: client,
      includeMessageActions: false,
    );
    await placeholder.retract();
    return IncomingPushOutcome.message;
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
    timing: timing,
  );
  timing?.mark('refine');
  return IncomingPushOutcome.message;
}

class _Placeholder {
  _Placeholder(this.client, this.notification);

  final Client client;
  final PushNotification notification;
  bool _posted = false;

  Future<Event?> race(
    Future<Event?> Function() resolve, {
    required Duration after,
  }) async {
    final resolution = resolve();
    final settled = Completer<void>();
    unawaited(
      resolution.then((_) {}, onError: (_) {}).whenComplete(settled.complete),
    );
    await Future.any([settled.future, Future<void>.delayed(after)]);
    if (!settled.isCompleted) await post();
    return resolution;
  }

  Future<bool> post() async {
    if (_posted) return true;
    final content = unresolvedPushNotification(client, notification);
    if (content == null) return false;
    _posted = true;
    debugPrint('zuno/push: showing a placeholder while the fetch continues');
    await postMessageNotification(content, client: client, placeholder: true);
    return true;
  }

  Future<void> retract() async {
    final roomId = notification.roomId;
    final eventId = notification.eventId;
    if (roomId == null || eventId == null) return;
    await CallNotificationService.instance.retractPushNotice(roomId, eventId);
    if (!_posted) return;
    await CallNotificationService.instance.retractPlaceholder(roomId, eventId);
  }
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

Future<bool> _isResolved(String callId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return readResolvedCallIds(prefs).contains(callId);
  } catch (_) {
    return false;
  }
}

Future<void> _markResolved(String callId) async {
  try {
    await markCallResolvedOnDisk(await SharedPreferences.getInstance(), callId);
  } catch (_) {}
}

MessageNotificationContent? unresolvedPushNotification(
  Client client,
  PushNotification notification,
) {
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
  );
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

enum IncomingPushOutcome { ignored, message, callRinging, badge }
