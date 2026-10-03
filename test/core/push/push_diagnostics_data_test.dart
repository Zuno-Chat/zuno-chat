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

  test('server times are moved onto the device clock', () {
    final health = ServerHealth(
      voipRegistered: true,
      serverOffset: const Duration(minutes: 2),
    );
    expect(
      health.toDevice(DateTime(2026, 10, 2, 12, 2)),
      DateTime(2026, 10, 2, 12),
    );
  });
}
