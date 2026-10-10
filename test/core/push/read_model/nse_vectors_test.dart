import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/notifications/invite_notification_provider.dart';
import 'package:zuno/core/notifications/message_notification_provider.dart';
import 'package:zuno/core/notifications/notify_me.dart';
import 'package:zuno/core/notifications/verification_request_notification.dart';
import 'package:zuno/core/push/read_model/mention_spec.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fixtures.dart';

const _roomId = '!abc:zuno.im';

Event _state(Room room, String type, Map<String, dynamic> content) => Event(
  type: type,
  content: content,
  senderId: '@admin:zuno.im',
  eventId: '\$state_$type',
  originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
  stateKey: '',
  room: room,
);

Map<String, Object?> _dispatch(Client client, Event event) {
  if (isCallSummaryMessage(event.messageType) && !isMissedCallSummary(event)) {
    return {'class': 'hidden'};
  }
  final call = incomingCallFromEvent(client, event);
  if (call != null) {
    return {
      'class': 'ring',
      'call_id': call.callId,
      'video': call.kind == CallKind.video,
    };
  }
  final invite = inviteNotificationFor(client, event);
  if (invite != null) {
    return {'class': 'invitation', 'title': invite.title, 'body': invite.body};
  }
  final verification = verificationRequestNotificationFor(client, event);
  if (verification != null) {
    return {
      'class': 'verification',
      'title': verification.title,
      'body': verification.body,
    };
  }
  final content = messageNotificationFor(
    client,
    event,
    pushRuleAction: EvaluatedPushRuleAction()..notify = true,
    notifyMe: NotifyMe.all,
    currentlyOpenRoomId: null,
  ).content;
  if (content == null) return {'class': 'hidden'};
  return {'class': 'message', 'title': content.title, 'body': content.body};
}

class _RulesClient extends Client {
  _RulesClient(this.rules) : super('test', database: FakeDatabaseApi());

  final PushRuleSet rules;

  @override
  PushruleEvaluator get pushruleEvaluator =>
      PushruleEvaluator.fromRuleset(rules);
}

void main() {
  setUp(ringRateLimiter.clear);

  group('dispatch vectors match the Android handler', () {
    final fixture = pushFixture('nse_dispatch_v1.json');
    final me = fixture['me'] as String;
    for (final raw in fixture['cases'] as List) {
      final vector = raw as Map<String, dynamic>;
      test(vector['name'] as String, () {
        final client = buildTestClient(userId: me);
        final room = buildTestRoom(client, id: _roomId);
        final roomJson = vector['room'] as Map<String, dynamic>;
        final event = vector['event'] as Map<String, dynamic>;
        final sender = vector['sender'] as String;
        final isMember = event['type'] == EventTypes.RoomMember;
        final name =
            roomJson['name'] as String? ??
            (isMember ? null : roomJson['title'] as String?);
        if (name != null) {
          room.setState(_state(room, EventTypes.RoomName, {'name': name}));
        }
        room.setState(
          _state(room, EventTypes.RoomPowerLevels, {
            'users': {me: 100},
            'users_default': 0,
            'state_default': 50,
            'events': <String, dynamic>{},
          }),
        );
        room.setState(User(me, displayName: fixture['me_name'], room: room));
        final senderName = vector['sender_name'] as String?;
        if (senderName != null && sender != me) {
          room.setState(User(sender, displayName: senderName, room: room));
        }
        if (roomJson['dm'] == true) {
          client.accountData['m.direct'] = BasicEvent(
            type: 'm.direct',
            content: {
              sender: [_roomId],
            },
          );
        }
        final matrixEvent = Event(
          type: event['type'] as String,
          content: Map<String, dynamic>.from(event['content'] as Map),
          senderId: sender,
          eventId: r'$vector',
          originServerTs: DateTime.now().subtract(
            Duration(milliseconds: vector['age_ms'] as int),
          ),
          stateKey: event['state_key'] as String?,
          room: room,
          unsigned: event['redacted'] == true
              ? {
                  'redacted_because': {
                    'type': EventTypes.Redaction,
                    'event_id': r'$redaction',
                    'sender': sender,
                    'origin_server_ts': 0,
                    'content': <String, dynamic>{},
                    'redacts': r'$vector',
                  },
                }
              : null,
        );

        expect(_dispatch(client, matrixEvent), vector['expect']);
      });
    }
  });

  group('html vectors match the SDK plain text', () {
    final fixture = pushFixture('nse_html_v1.json');
    final client = buildTestClient(userId: '@mwong:zuno.im');
    final room = buildTestRoom(client, id: _roomId);
    for (final raw in fixture['cases'] as List) {
      final vector = raw as Map<String, dynamic>;
      test(jsonEncode(vector['html']), () {
        final event = buildTestEvent(
          room,
          eventId: r'$html',
          senderId: '@alice:zuno.im',
          content: {
            'msgtype': MessageTypes.Text,
            'body': 'fallback',
            'format': 'org.matrix.custom.html',
            'formatted_body': vector['html'],
          },
        );

        expect(event.plaintextBody, vector['text']);
      });
    }
  });

  group('mention vectors match the push rule evaluator', () {
    final fixture = pushFixture('nse_mentions_v1.json');
    final me = fixture['me'] as String;
    final rulesets = fixture['rulesets'] as Map<String, dynamic>;
    final specs = fixture['specs'] as Map<String, dynamic>;
    for (final raw in fixture['cases'] as List) {
      final vector = raw as Map<String, dynamic>;
      test(vector['name'] as String, () {
        final name = vector['rules'] as String;
        final rules = PushRuleSet.fromJson(
          rulesets[name] as Map<String, dynamic>,
        );
        final client = _RulesClient(rules)..setUserId(me);
        final room = buildTestRoom(client, id: _roomId);
        room.setState(
          _state(
            room,
            EventTypes.RoomPowerLevels,
            Map<String, dynamic>.from(fixture['power_levels'] as Map),
          ),
        );
        room.setState(User(me, displayName: fixture['me_name'], room: room));
        final sender = vector['sender'] as String;
        room.setState(User(sender, displayName: 'Sender', room: room));
        final event = buildTestEvent(
          room,
          eventId: r'$mention',
          senderId: sender,
          content: Map<String, Object?>.from(vector['content'] as Map),
        );

        expect(
          client.pushruleEvaluator.match(event).highlight,
          vector['mention'],
        );
        expect(
          mentionSpecOf(rules, mxid: me, displayName: fixture['me_name']),
          specs[name],
        );
        expect(roomNotifiers(room), fixture['notifiers']);
      });
    }
  });
}
