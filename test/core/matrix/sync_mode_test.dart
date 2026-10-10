import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/sync_coordinator.dart';

void main() {
  group('syncModeFor', () {
    const cases = <(Set<SyncReason>, bool, SyncMode)>[
      ({}, true, SyncMode.off),
      ({}, false, SyncMode.off),
      ({SyncReason.foreground}, true, SyncMode.live),
      ({SyncReason.foreground}, false, SyncMode.live),
      ({SyncReason.call}, false, SyncMode.live),
      ({SyncReason.ring}, true, SyncMode.live),
      ({SyncReason.liveShare}, true, SyncMode.background),
      ({SyncReason.delivery}, true, SyncMode.background),
      ({SyncReason.liveShare, SyncReason.delivery}, false, SyncMode.off),
      ({SyncReason.liveShare, SyncReason.call}, false, SyncMode.live),
      ({SyncReason.delivery, SyncReason.foreground}, true, SyncMode.live),
    ];

    for (final (reasons, network, mode) in cases) {
      test('$reasons with${network ? '' : 'out'} network is ${mode.name}', () {
        expect(syncModeFor(reasons, networkAvailable: network), mode);
      });
    }
  });

  group('backgroundRetryDelay', () {
    const cases = <(int, Duration?)>[
      (0, null),
      (2, null),
      (3, Duration(seconds: 10)),
      (4, Duration(seconds: 20)),
      (7, Duration(seconds: 160)),
      (8, Duration(minutes: 5)),
      (40, Duration(minutes: 5)),
    ];

    for (final (failures, delay) in cases) {
      test('$failures failures in a row wait $delay', () {
        expect(backgroundRetryDelay(failures), delay);
      });
    }
  });
}
