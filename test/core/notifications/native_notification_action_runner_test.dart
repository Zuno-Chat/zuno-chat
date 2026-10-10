import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/notifications/message_notification_action.dart';
import 'package:zuno/core/notifications/native_notification_action_runner.dart';
import 'package:zuno/core/notifications/native_notification_actions.dart';
import 'package:zuno/core/notifications/notification_action_target.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/notification_actions');
  const wakeLock = MethodChannel('zuno/wake_lock');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final enabled = capabilitiesLike(
    iosCapabilities,
    nativeNotificationActions: true,
  );
  late Client client;
  late List<String> requests;
  late List<Map<String, Object?>> bodies;
  late List<List<Object?>> queued;
  late List<Map<Object?, Object?>> finished;
  late List<String> nativeCalls;
  late List<String> order;
  late List<String> acquired;
  late List<String> released;
  Completer<http.Response>? stalledMarker;

  setUp(() {
    requests = [];
    bodies = [];
    queued = [];
    finished = [];
    nativeCalls = [];
    order = [];
    acquired = [];
    released = [];
    stalledMarker = null;
    client = buildTestClient(
      userId: '@me:example.org',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        final step = switch (path) {
          _ when path.contains('/send/') => 'send',
          _ when path.contains('read_markers') => 'read',
          _ => 'other',
        };
        requests.add('${request.method} $path');
        order.add(step);
        if (request.body.isNotEmpty) {
          bodies.add(jsonDecode(request.body) as Map<String, Object?>);
        }
        if (step == 'send') {
          return http.Response(jsonEncode({'event_id': r'$sent'}), 200);
        }
        final stalled = stalledMarker;
        if (stalled != null && step == 'read') return stalled.future;
        return http.Response('{}', 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    client.rooms.add(buildTestRoom(client));
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      switch (call.method) {
        case 'takeActions':
          return queued.isEmpty ? <Object?>[] : queued.removeAt(0);
        case 'finish':
          finished.add(call.arguments as Map<Object?, Object?>);
          order.add('finish');
      }
      return null;
    });
    messenger.setMockMethodCallHandler(wakeLock, (call) async {
      order.add(call.method);
      final tag = (call.arguments as Map)['tag'] as String;
      (call.method == 'acquire' ? acquired : released).add(tag);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(wakeLock, null);
    channel.setMethodCallHandler(null);
  });

  NativeNotificationActionRunner runner({
    MarkReadEventFinder? markReadEvent,
    MessageActionPerformer? perform,
    Duration budget = nativeActionBudget,
  }) => NativeNotificationActionRunner(
    channel: NativeNotificationActionsChannel(capabilities: enabled),
    rooms: ThreadKeyRooms(
      threadKeyFor: (id) async =>
          id == '!room:example.org' ? 'token-room' : 'token-other',
    ),
    markReadEvent: markReadEvent ?? (room, action) async => action.eventId,
    perform: perform,
    budget: budget,
    wakeLock: HeadlessWakeLock(capabilities: enabled, tag: 'follow_up'),
  );

  Future<void> attachAndDrain(NativeNotificationActionRunner subject) async {
    subject.attach(client);
    await subject.drain();
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await pumpEventQueue();
    }
  }

  test('a Reply is sent by the app client under its own transaction id, then '
      'reported done', () async {
    queued.add([
      {
        'id': 'a1',
        'kind': 'reply',
        'roomId': '!room:example.org',
        'replyText': 'on my way',
      },
    ]);

    await attachAndDrain(runner());

    expect(
      requests.where((r) => r.contains('/send/')).single,
      endsWith('/zuno-notification-a1'),
    );
    expect(bodies.single['body'], 'on my way');
    expect(finished, [
      {'id': 'a1', 'ok': true},
    ]);
  });

  test('a Reply on an extension line takes a wake lock, is reported sent at '
      'once, then marks the room read and lets the lock go', () async {
    queued.add([
      {
        'id': 'a1',
        'kind': 'reply',
        'roomToken': 'token-room',
        'eventSeconds': 1790000000,
        'replyText': 'on my way',
      },
    ]);

    await attachAndDrain(
      runner(markReadEvent: (room, action) async => r'$notified'),
    );
    await until(() => order.contains('release'));

    expect(order, ['send', 'acquire', 'finish', 'read', 'release']);
    expect(released, acquired);
    expect(bodies.last['m.fully_read'], r'$notified');
    expect(finished, [
      {'id': 'a1', 'ok': true},
    ]);
  });

  test('a Reply that carries an event id is reported sent even when its read '
      'marker never completes, then attempts the marker', () async {
    final stalled = Completer<http.Response>();
    stalledMarker = stalled;
    queued.add([
      {
        'id': 'a1',
        'kind': 'reply',
        'roomId': '!room:example.org',
        'eventId': r'$notified',
        'replyText': 'on my way',
      },
    ]);

    final drained = attachAndDrain(runner(budget: const Duration(seconds: 1)));
    await until(() => finished.isNotEmpty);

    expect(finished, [
      {'id': 'a1', 'ok': true},
    ]);
    await until(() => order.contains('read'));
    expect(order, ['send', 'acquire', 'finish', 'read']);
    expect(bodies.last['m.fully_read'], r'$notified');

    stalled.complete(http.Response('{}', 200));
    await drained;
    await until(() => order.contains('release'));
    expect(order, ['send', 'acquire', 'finish', 'read', 'release']);
  });

  test('a second queued Reply is sent while the first one\'s read marker is '
      'still in flight, and each marker holds its own wake lock', () async {
    final stalled = Completer<http.Response>();
    stalledMarker = stalled;
    queued.add([
      {
        'id': 'a1',
        'kind': 'reply',
        'roomId': '!room:example.org',
        'replyText': 'one',
      },
      {
        'id': 'a2',
        'kind': 'reply',
        'roomId': '!room:example.org',
        'replyText': 'two',
      },
    ]);

    final drained = attachAndDrain(
      runner(markReadEvent: (room, action) async => r'$notified'),
    );
    await until(() => finished.length == 2);

    expect(finished, [
      {'id': 'a1', 'ok': true},
      {'id': 'a2', 'ok': true},
    ]);
    expect(acquired.toSet(), hasLength(2));
    expect(order.indexOf('acquire'), lessThan(order.indexOf('finish')));
    expect(order.lastIndexOf('acquire'), lessThan(order.lastIndexOf('finish')));
    expect(released, isEmpty);

    stalled.complete(http.Response('{}', 200));
    await drained;
    await until(() => released.length == 2);
    expect(released, unorderedEquals(acquired));
    expect(order.where((entry) => entry == 'read'), hasLength(2));
  });

  test('a read marker that fails still lets the wake lock go', () async {
    queued.add([
      {
        'id': 'a1',
        'kind': 'reply',
        'roomId': '!room:example.org',
        'replyText': 'on my way',
      },
    ]);

    await attachAndDrain(
      runner(markReadEvent: (room, action) async => throw Exception('gone')),
    );
    await until(() => order.contains('release'));

    expect(order, ['send', 'acquire', 'finish', 'release']);
    expect(released, acquired);
  });

  test('an action that does not finish within its budget is reported not '
      'done', () async {
    queued.add([
      {
        'id': 'a1',
        'kind': 'reply',
        'roomId': '!room:example.org',
        'replyText': 'hi',
      },
    ]);

    await attachAndDrain(
      NativeNotificationActionRunner(
        channel: NativeNotificationActionsChannel(capabilities: enabled),
        perform: (room, action, txid) => Completer<void>().future,
        budget: const Duration(milliseconds: 20),
      ),
    );

    expect(finished, [
      {'id': 'a1', 'ok': false},
    ]);
  });

  test('Mark as read found by its room token marks the room read up to the '
      'notified event', () async {
    queued.add([
      {
        'id': 'm1',
        'kind': 'markRead',
        'roomToken': 'token-room',
        'eventSeconds': 1790000000,
      },
    ]);

    await attachAndDrain(
      runner(markReadEvent: (room, action) async => r'$notified'),
    );

    expect(requests.single, contains('read_markers'));
    expect(bodies.single['m.fully_read'], r'$notified');
    expect(acquired, isEmpty);
    expect(finished, [
      {'id': 'm1', 'ok': true},
    ]);
  });

  test(
    'an action for a room this account is not in is reported not done',
    () async {
      queued.add([
        {
          'id': 'm1',
          'kind': 'markRead',
          'roomId': '!gone:example.org',
          'eventId': r'$e',
        },
      ]);

      await attachAndDrain(runner());

      expect(requests, isEmpty);
      expect(finished, [
        {'id': 'm1', 'ok': false},
      ]);
    },
  );

  test(
    'after sign-out nothing is sent and the action is reported not done',
    () async {
      client.bearerToken = null;
      queued.add([
        {
          'id': 'a1',
          'kind': 'reply',
          'roomId': '!room:example.org',
          'replyText': 'hi',
        },
      ]);

      await attachAndDrain(runner());

      expect(requests, isEmpty);
      expect(finished, [
        {'id': 'a1', 'ok': false},
      ]);
    },
  );

  test('a send that keeps failing is reported not done', () async {
    queued.add([
      {
        'id': 'a1',
        'kind': 'reply',
        'roomId': '!room:example.org',
        'replyText': 'hi',
      },
    ]);

    await attachAndDrain(
      runner(perform: (room, action, txid) async => throw Exception('offline')),
    );

    expect(finished, [
      {'id': 'a1', 'ok': false},
    ]);
  });

  test('Mark as read with no event to mark is reported not done', () async {
    queued.add([
      {'id': 'm1', 'kind': 'markRead', 'roomId': '!room:example.org'},
    ]);

    await attachAndDrain(runner(markReadEvent: (room, action) async => null));

    expect(requests, isEmpty);
    expect(finished, [
      {'id': 'm1', 'ok': false},
    ]);
  });

  test('an entry Zuno cannot read is finished as not done', () async {
    queued.add([
      {'id': 'bad', 'kind': 'forward', 'roomId': '!room:example.org'},
    ]);

    await attachAndDrain(runner());

    expect(finished, [
      {'id': 'bad', 'ok': false},
    ]);
  });

  test('the native hint drains the actions that arrived since', () async {
    final subject = runner();
    await attachAndDrain(subject);
    queued.add([
      {
        'id': 'm2',
        'kind': 'markRead',
        'roomId': '!room:example.org',
        'eventId': r'$e2',
      },
    ]);

    await callFromNative(channel, 'actionsAvailable');
    await subject.drain();

    expect(finished.last, {'id': 'm2', 'ok': true});
  });

  test('without native actions attaching does nothing', () async {
    final subject = NativeNotificationActionRunner(
      channel: NativeNotificationActionsChannel(
        capabilities: androidCapabilities,
      ),
    );

    subject.attach(client);
    await subject.drain();

    expect(nativeCalls, isEmpty);
    expect(requests, isEmpty);
  });
}
