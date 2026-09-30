import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/platform/system_call.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/platform_capabilities.dart';

const _roomId = '!room:example.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/calls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RecordedCallsChannel native;
  late Object? startReply;

  setUp(() {
    startReply = {'muted': false};
    native = installFakeCallsChannel(
      reply: (call) => call.method == 'startSystemCall' ? startReply : null,
    );
  });

  List<Object?> sent() => [
    for (final call in native.calls) [call.method, call.arguments],
  ];

  Future<SystemCallStart> beginOn(SystemCall systemCall) => systemCall.begin(
    roomId: _roomId,
    callId: 'call1',
    title: 'Weekend hike',
    isVideo: true,
  );

  Future<void> reportEverythingOn(SystemCall systemCall) async {
    await systemCall.connected(roomId: _roomId, callId: 'call1');
    await systemCall.setMuted(roomId: _roomId, callId: 'call1', muted: true);
    await systemCall.upgradeToVideo(roomId: _roomId, callId: 'call1');
    await systemCall.end(
      roomId: _roomId,
      callId: 'call1',
      end: SystemCallEnd.remoteEnded,
      byUser: true,
    );
  }

  group('the CallKit system call', () {
    const systemCall = CallKitSystemCall();

    test(
      'starts the call with the room, title and kind CallKit shows',
      () async {
        await beginOn(systemCall);

        expect(sent(), [
          [
            'startSystemCall',
            {
              'roomId': _roomId,
              'callId': 'call1',
              'title': 'Weekend hike',
              'isVideo': true,
            },
          ],
        ]);
      },
    );

    test('starts muted when CallKit already holds the call muted', () async {
      startReply = {'muted': true};

      expect((await beginOn(systemCall)).muted, isTrue);
    });

    test(
      'starts unmuted when CallKit says so or says nothing about it',
      () async {
        for (final reply in [
          {'muted': false},
          {'muted': null},
          {'muted': 'true'},
          <String, Object?>{},
          null,
        ]) {
          startReply = reply;

          expect((await beginOn(systemCall)).muted, isFalse, reason: '$reply');
        }
      },
    );

    test('starts unmuted when there is no platform side', () async {
      messenger.setMockMethodCallHandler(channel, null);

      expect((await beginOn(systemCall)).muted, isFalse);
    });

    test('reports the connection, each mute change and the switch to video, '
        'naming the call each time', () async {
      await systemCall.connected(roomId: _roomId, callId: 'call1');
      await systemCall.setMuted(roomId: _roomId, callId: 'call1', muted: true);
      await systemCall.setMuted(roomId: _roomId, callId: 'call1', muted: false);
      await systemCall.upgradeToVideo(roomId: _roomId, callId: 'call1');

      expect(sent(), [
        [
          'reportCallConnected',
          {'roomId': _roomId, 'callId': 'call1'},
        ],
        [
          'setCallMuted',
          {'roomId': _roomId, 'callId': 'call1', 'muted': true},
        ],
        [
          'setCallMuted',
          {'roomId': _roomId, 'callId': 'call1', 'muted': false},
        ],
        [
          'upgradeCallToVideo',
          {'roomId': _roomId, 'callId': 'call1'},
        ],
      ]);
    });

    test(
      'ends the call with a reason CallKit knows and who ended it',
      () async {
        const reasons = {
          SystemCallEnd.remoteEnded: 'remoteEnded',
          SystemCallEnd.unanswered: 'unanswered',
          SystemCallEnd.failed: 'failed',
        };

        for (final end in SystemCallEnd.values) {
          await systemCall.end(
            roomId: _roomId,
            callId: 'call1',
            end: end,
            byUser: end == SystemCallEnd.remoteEnded,
          );
        }

        expect(sent(), [
          for (final end in SystemCallEnd.values)
            [
              'endSystemCall',
              {
                'roomId': _roomId,
                'callId': 'call1',
                'reason': reasons[end],
                'byUser': end == SystemCallEnd.remoteEnded,
              },
            ],
        ]);
      },
    );

    test('a missing platform side is not an error for any report', () async {
      messenger.setMockMethodCallHandler(channel, null);

      await expectLater(reportEverythingOn(systemCall), completes);
    });
  });

  group('without CallKit', () {
    test('android reports nothing and starts every call unmuted', () async {
      final systemCall = systemCallFor(androidCapabilities);
      startReply = {'muted': true};

      final start = await beginOn(systemCall);
      await reportEverythingOn(systemCall);

      expect(systemCall, isA<NoopSystemCall>());
      expect(start.muted, isFalse);
      expect(native.calls, isEmpty);
    });
  });

  group('picking the system call', () {
    test('ios reports its calls to CallKit', () {
      expect(systemCallFor(iosCapabilities), isA<CallKitSystemCall>());
    });

    test('CallKit, not the platform name, decides', () {
      expect(
        systemCallFor(capabilitiesLike(iosCapabilities, callKit: false)),
        isA<NoopSystemCall>(),
      );
      expect(
        systemCallFor(capabilitiesLike(androidCapabilities, callKit: true)),
        isA<CallKitSystemCall>(),
      );
    });

    test('the provider follows the platform capabilities', () {
      final android = ProviderContainer();
      addTearDown(android.dispose);
      final ios = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(iosCapabilities),
        ],
      );
      addTearDown(ios.dispose);

      expect(android.read(systemCallProvider), isA<NoopSystemCall>());
      expect(ios.read(systemCallProvider), isA<CallKitSystemCall>());
    });
  });
}
