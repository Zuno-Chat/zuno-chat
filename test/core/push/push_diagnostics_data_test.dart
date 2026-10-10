import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/push/push_diagnostics_data.dart';

void main() {
  group('PushDiagnosticsSnapshot', () {
    test('reads the settings, environment, ledger, shared data, extension and '
        'device reports', () {
      final snapshot = PushDiagnosticsSnapshot.fromChannel({
        'settings': {
          'authorization': 'authorized',
          'providesAppSettings': false,
          'badge': 2,
          'ignored': ['x'],
        },
        'environment': 'development',
        'ledger': [
          {'state': 'answered', 'source': 'push', 'ts': 1790000000000},
          {'state': 'missed', 'source': 'sync'},
          'junk',
        ],
        'read_model': {'updated_ms': 1790000100000},
        'nse': {
          'last_run_ms': 1790000200000,
          'version': '1.2.0 (2)',
          'log': ['shown', 7, 'utd'],
        },
        'metrics': [
          {
            'kind': 'exits',
            'end_ms': 1790000300000,
            'counts': {'locked_file': 2, 'memory': 0},
          },
          {'kind': 'crash'},
        ],
      });

      expect(snapshot.settings, {
        'authorization': 'authorized',
        'providesAppSettings': 'false',
        'badge': '2',
      });
      expect(snapshot.environment, 'development');
      expect(snapshot.ledger!.single.state, 'answered');
      expect(snapshot.ledger!.single.source, 'push');
      expect(
        snapshot.ledger!.single.at,
        DateTime.fromMillisecondsSinceEpoch(1790000000000),
      );
      expect(
        snapshot.readModelUpdatedAt,
        DateTime.fromMillisecondsSinceEpoch(1790000100000),
      );
      expect(
        snapshot.extensionLastRun,
        DateTime.fromMillisecondsSinceEpoch(1790000200000),
      );
      expect(snapshot.extensionVersion, '1.2.0 (2)');
      expect(snapshot.extensionLog, ['shown', 'utd']);
      expect(snapshot.metrics.single.kind, 'exits');
      expect(snapshot.metrics.single.counts, {'locked_file': 2});
    });

    test('anything that is not a snapshot reads as an empty one', () {
      for (final raw in [null, 'x', 3, <Object?>[]]) {
        final snapshot = PushDiagnosticsSnapshot.fromChannel(raw);
        expect(snapshot.settings, isEmpty);
        expect(snapshot.ledger, isNull);
        expect(snapshot.extensionLog, isEmpty);
        expect(snapshot.environment, isNull);
      }
    });

    test('a ledger read as empty is none, a ledger that was not read is '
        'unknown', () {
      expect(
        PushDiagnosticsSnapshot.fromChannel({'ledger': <Object?>[]}).ledger,
        isEmpty,
      );
      expect(
        PushDiagnosticsSnapshot.fromChannel({
          'ledger': <Object?>['junk'],
        }).ledger,
        isEmpty,
      );
      for (final raw in [
        <String, Object?>{},
        {'ledger': null},
        {'ledger': 'x'},
      ]) {
        expect(PushDiagnosticsSnapshot.fromChannel(raw).ledger, isNull);
      }
    });

    test('pieces of the wrong shape are left out, the rest kept', () {
      final snapshot = PushDiagnosticsSnapshot.fromChannel({
        'settings': 'x',
        'environment': '',
        'ledger': {'state': 'answered'},
        'read_model': {'updated_ms': -1},
        'nse': {'log': 'not a list', 'last_run_ms': 'soon'},
      });
      expect(snapshot.settings, isEmpty);
      expect(snapshot.environment, isNull);
      expect(snapshot.ledger, isNull);
      expect(snapshot.readModelUpdatedAt, isNull);
      expect(snapshot.extensionLastRun, isNull);
      expect(snapshot.extensionLog, isEmpty);
    });
  });

  test('reads the app log and the Android part, leaving out what failed', () {
    final snapshot = PushDiagnosticsSnapshot.fromChannel({
      'app': {
        'log': ['ring', 3],
      },
      'notificationsEnabled': true,
      'channels': [
        {
          'id': 'direct_messages',
          'name': 'Chat messages',
          'importance': 'high',
        },
        {'id': 'broken'},
      ],
      'fullScreenIntent': false,
      'backgroundData': 'restricted',
      'standbyBucket': 45,
    });

    expect(snapshot.appLog, ['ring']);
    final android = snapshot.android;
    expect(android.notificationsEnabled, isTrue);
    expect(android.channels?.single.name, 'Chat messages');
    expect(android.fullScreenIntent, isFalse);
    expect(android.batteryOptimizationIgnored, isNull);
    expect(android.backgroundData, 'restricted');
    expect(android.standbyBucket, 45);
  });

  test('an Apple snapshot has an empty Android part', () {
    final android = PushDiagnosticsSnapshot.fromChannel({
      'settings': <String, Object?>{},
    }).android;

    expect(android.notificationsEnabled, isNull);
    expect(android.channels, isNull);
  });

  test('reads whether the system gave the device a token', () {
    bool? registered(Map<String, Object?> raw) =>
        PushDiagnosticsSnapshot.fromChannel(raw)
            .registeredForRemoteNotifications;

    expect(registered({'registeredForRemoteNotifications': true}), isTrue);
    expect(registered({'registeredForRemoteNotifications': false}), isFalse);
    expect(registered({}), isNull);
  });
}
