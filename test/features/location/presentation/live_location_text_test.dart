import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_sharing.dart';
import 'package:zuno/core/location/live_location_viewing.dart';
import 'package:zuno/features/location/presentation/live_location_text.dart';

import '../../../helpers/date_labels.dart';

void main() {
  final now = DateTime(2026, 10, 7, 14);
  final labels = testDateLabels();

  LiveShareView share({
    Duration? updatedAgo,
    bool fromThisDevice = false,
    DateTime? refreshingSince,
  }) => LiveShareView(
    userId: '@alex:x',
    shareId: 's',
    deviceId: 'PHONE',
    endsAt: DateTime(2026, 10, 7, 15, 30),
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
          labels,
        ),
        'Until 15:30 · updating, last updated 4 min ago',
      );
      expect(
        liveShareStatusText(
          share(updatedAgo: const Duration(minutes: 20), refreshingSince: now),
          now,
          labels,
        ),
        'Until 15:30 · updating, not updated since 13:40',
      );
    });

    test('past the stale window reads a clock time, never an hour count', () {
      expect(
        liveShareStatusText(
          share(updatedAgo: const Duration(minutes: 90)),
          now,
          labels,
        ),
        'Until 15:30 · not updated since 12:30',
      );
    });

    test('says how fresh a live position is', () {
      expect(
        liveShareStatusText(share(updatedAgo: Duration.zero), now, labels),
        'Until 15:30 · updated just now',
      );
      expect(
        liveShareStatusText(
          share(updatedAgo: const Duration(minutes: 4)),
          now,
          labels,
        ),
        'Until 15:30 · updated 4 min ago',
      );
    });

    test('says when a position is still on its way', () {
      expect(
        liveShareStatusText(share(), now, labels),
        'Until 15:30 · waiting for location',
      );
    });

    test('says since when a share has not updated', () {
      expect(
        liveShareStatusText(
          share(updatedAgo: const Duration(minutes: 20)),
          now,
          labels,
        ),
        'Until 15:30 · not updated since 13:40',
      );
    });

    test('names only the end for this device\'s own share', () {
      expect(
        liveShareStatusText(
          share(updatedAgo: Duration.zero, fromThisDevice: true),
          now,
          labels,
        ),
        'Until 15:30',
      );
    });
  });

  group('who is sharing', () {
    String sharers(List<String> others, {required bool includesYou}) =>
        liveSharersText(englishLocalizations, others, includesYou: includesYou);

    test('reads naturally for every mix', () {
      const six = ['Alex', 'Bea', 'Carl', 'Dee', 'Eve', 'Fay'];
      expect(
        sharers(const [], includesYou: true),
        'You are sharing your live location',
      );
      expect(
        sharers(const ['Alex'], includesYou: false),
        'Alex is sharing live location',
      );
      expect(
        sharers(const ['Alex'], includesYou: true),
        'You and Alex are sharing live location',
      );
      expect(
        sharers(const ['Alex', 'Bea'], includesYou: false),
        'Alex and Bea are sharing live location',
      );
      expect(
        sharers(const ['Alex', 'Bea', 'Carl'], includesYou: false),
        'Alex and 2 others are sharing live location',
      );
      expect(
        sharers(six, includesYou: false),
        'Alex and 5 others are sharing live location',
      );
      expect(
        sharers(six, includesYou: true),
        'You and 6 others are sharing live location',
      );
      expect(
        sharers(const ['Alex', 'Bea'], includesYou: true),
        'You and 2 others are sharing live location',
      );
    });
  });

  test('a failed start says what to do next', () {
    expect(
      LiveShareStartFailure.values.map(
        (reason) => liveShareStartFailureText(englishLocalizations, reason),
      ),
      [
        'You cannot share live location here.',
        'You are already sharing your live location here.',
        'Live location could not start. Check that location is on, then try again.',
        'Live location did not start.',
      ],
    );
  });
}
