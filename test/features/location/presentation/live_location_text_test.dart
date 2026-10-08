import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_sharing.dart';
import 'package:zuno/core/location/live_location_viewing.dart';
import 'package:zuno/features/location/presentation/live_location_text.dart';

void main() {
  final now = DateTime.utc(2026, 10, 7, 14);
  String clock(DateTime time) => '${time.hour}:${time.minute}';

  LiveShareView share({
    Duration? updatedAgo,
    bool fromThisDevice = false,
    DateTime? refreshingSince,
  }) => LiveShareView(
    userId: '@alex:x',
    shareId: 's',
    deviceId: 'PHONE',
    endsAt: DateTime.utc(2026, 10, 7, 15, 30),
    position: updatedAgo == null
        ? null
        : LivePosition(
            geo: const GeoUri(latitude: 1, longitude: 2),
            at: now.subtract(updatedAgo),
          ),
    fromThisDevice: fromThisDevice,
    refreshingSince: refreshingSince,
  );

  group('status', () {
    test('says it is updating while a stale share refreshes', () {
      expect(
        liveShareStatusText(
          share(updatedAgo: const Duration(minutes: 4), refreshingSince: now),
          now,
          clock,
        ),
        'Until 15:30 · updating, last updated 4 min ago',
      );
      expect(
        liveShareStatusText(
          share(updatedAgo: const Duration(minutes: 20), refreshingSince: now),
          now,
          clock,
        ),
        'Until 15:30 · updating, not updated since 13:40',
      );
    });

    test('drops the updating once it gives up', () {
      expect(
        liveShareStatusText(
          share(
            updatedAgo: const Duration(minutes: 4),
            refreshingSince: now.subtract(const Duration(minutes: 3)),
          ),
          now,
          clock,
        ),
        'Until 15:30 · updated 4 min ago',
      );
    });

    test('says how fresh a live position is', () {
      expect(
        liveShareStatusText(share(updatedAgo: Duration.zero), now, clock),
        'Until 15:30 · updated just now',
      );
      expect(
        liveShareStatusText(
          share(updatedAgo: const Duration(minutes: 4)),
          now,
          clock,
        ),
        'Until 15:30 · updated 4 min ago',
      );
    });

    test('says when a position is still on its way', () {
      expect(
        liveShareStatusText(share(), now, clock),
        'Until 15:30 · waiting for location',
      );
    });

    test('says since when a share has not updated', () {
      expect(
        liveShareStatusText(
          share(updatedAgo: const Duration(minutes: 20)),
          now,
          clock,
        ),
        'Until 15:30 · not updated since 13:40',
      );
    });

    test('names only the end for this device\'s own share', () {
      expect(
        liveShareStatusText(
          share(updatedAgo: Duration.zero, fromThisDevice: true),
          now,
          clock,
        ),
        'Until 15:30',
      );
    });
  });

  group('who is sharing', () {
    test('reads naturally for every mix', () {
      expect(
        liveSharersText(const [], includesYou: true),
        'You are sharing your live location',
      );
      expect(
        liveSharersText(const ['Alex'], includesYou: false),
        'Alex is sharing live location',
      );
      expect(
        liveSharersText(const ['Alex'], includesYou: true),
        'You and Alex are sharing live location',
      );
      expect(
        liveSharersText(const ['Alex', 'Bea'], includesYou: false),
        'Alex and Bea are sharing live location',
      );
      expect(
        liveSharersText(const ['Alex', 'Bea', 'Carl'], includesYou: false),
        'Alex and 2 others are sharing live location',
      );
      expect(
        liveSharersText(const ['Alex', 'Bea'], includesYou: true),
        'You and 2 others are sharing live location',
      );
    });
  });

  test('a failed start says what to do next', () {
    expect(LiveShareStartFailure.values.map(liveShareStartFailureText), [
      'You cannot share live location here.',
      'You are already sharing your live location here.',
      'Live location could not start. Check that location is on, then try again.',
      'Live location did not start. Try again.',
    ]);
  });
}
