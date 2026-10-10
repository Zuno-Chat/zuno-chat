import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/push_test_client.dart';

class _BrokenClient extends Client {
  _BrokenClient() : super('test', database: FakeDatabaseApi());

  @override
  bool isLogged() => throw StateError('database closed');
}

Uint8List _pushBytes({String eventId = '\$abc'}) => utf8.encode(
  jsonEncode({
    'notification': {'event_id': eventId, 'room_id': '!room:example.org'},
  }),
);

Uint8List _badgeBytes() => utf8.encode(
  jsonEncode({
    'notification': {
      'counts': {'unread': 2},
    },
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UnifiedPushDeliveryProvider provider;
  late List<PushTestClient> built;
  late List<IncomingPushOutcome> handled;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = UnifiedPushDeliveryProvider();
    built = [];
    handled = [];
  });

  Future<Client> buildClient() async {
    final client = PushTestClient();
    built.add(client);
    return client;
  }

  Future<void> registerHeadless() => provider.ensureHeadlessCallbacksRegistered(
    clientBuilder: buildClient,
    onPushHandled: (outcome) async => handled.add(outcome),
  );

  Future<void> deliver({String eventId = '\$abc'}) => provider
      .deliverPushForTest(PushMessage(_pushBytes(eventId: eventId), true));

  group('the push wake lock', () {
    const channel = MethodChannel('zuno/push_wakelock');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> calls;
    late List<Object?> releasedFor;

    int releases() => calls.where((c) => c == 'release').length;

    setUp(() {
      calls = [];
      releasedFor = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'release') releasedFor.add(call.arguments);
        return call.method == 'appInFront' ? true : null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    group('in the app', () {
      test('is let go once its push is handled, naming the push it was held '
          'for', () async {
        await provider.ensureCallbacksRegistered(PushTestClient());

        await deliver(eventId: r'$held');

        expect(calls, ['release']);
        expect(releasedFor, [
          {'key': r'$held'},
        ]);
      });

      test('is let go once for a push left to the app\'s own sync', () async {
        await provider.ensureCallbacksRegistered(PushTestClient());
        provider.runner.isAppSyncing = () => true;

        await deliver();

        expect(releases(), 1);
      });

      test('is let go once for a push whose handling fails', () async {
        await provider.ensureCallbacksRegistered(_BrokenClient());

        await deliver();

        expect(releases(), 1);
      });
    });

    group('in a headless engine', () {
      test('is let go only after a ring hold ends', () async {
        final holdOver = Completer<void>();
        await provider.ensureHeadlessCallbacksRegistered(
          clientBuilder: buildClient,
          onPushHandled: (_) => holdOver.future,
        );

        final delivery = deliver();
        await pumpEventQueue();
        expect(calls, isEmpty);

        holdOver.complete();
        await delivery;
        expect(calls, ['release']);
      });

      test('is let go for a push it cannot read, which opens no '
          'client', () async {
        await registerHeadless();

        await provider.deliverPushForTest(
          PushMessage(utf8.encode('not json'), true),
        );

        expect(built, isEmpty);
        expect(handled, isEmpty);
        expect(calls, ['release']);
      });

      test('is let go when no client can be opened, and the failure is '
          'swallowed', () async {
        await provider.ensureHeadlessCallbacksRegistered(
          clientBuilder: () async => throw StateError('database unavailable'),
          onPushHandled: (outcome) async => handled.add(outcome),
        );

        await deliver();

        expect(handled, isEmpty);
        expect(calls, ['release']);
      });

      test('is let go once for a badge-only push', () async {
        await registerHeadless();

        await provider.deliverPushForTest(PushMessage(_badgeBytes(), true));

        expect(handled, [IncomingPushOutcome.badge]);
        expect(calls, ['release']);
      });

      test('is let go once for a signed-out push', () async {
        await provider.ensureHeadlessCallbacksRegistered(
          clientBuilder: () async => PushTestClient(signedIn: false),
          onPushHandled: (outcome) async => handled.add(outcome),
        );

        await deliver();

        expect(calls, ['release']);
      });
    });
  });

  test('the main isolate keeps its long-lived client', () async {
    final client = PushTestClient();
    await provider.ensureCallbacksRegistered(client);

    await provider.deliverPushForTest(PushMessage(_pushBytes(), true));

    expect(client.fetched, hasLength(1));
    expect(client.disposeCalls, 0);
    expect(built, isEmpty);
  });
}
