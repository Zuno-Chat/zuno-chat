import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_policy.dart';
import 'package:zuno/core/location/live_location_protocol.dart';

void main() {
  final start = DateTime.utc(2026, 10, 7, 12);

  LivePosition northBy(
    double meters, {
    Duration after = Duration.zero,
    double? u = 3,
  }) => LivePosition(
    geo: GeoUri(
      latitude: 52.5 + meters / (6378137 * pi / 180),
      longitude: 13.4,
      uncertaintyMeters: u,
    ),
    at: start.add(after),
  );

  LiveSendRecord sent(LivePosition position) =>
      LiveSendRecord(position: position, sentAt: position.at);

  LiveAudience? decide({
    required LivePosition latest,
    LiveSendRecord? toEveryone,
    LiveSendRecord? toWatchers,
    bool watchers = false,
    DateTime? now,
  }) => nextLiveAudience(
    latest: latest,
    lastToEveryone: toEveryone,
    lastToWatchers: toWatchers,
    hasWatchers: watchers,
    now: now ?? latest.at,
  );

  test('the first position goes to everyone', () {
    expect(decide(latest: northBy(0)), LiveAudience.everyone);
  });

  group('without watchers', () {
    final first = sent(northBy(0));

    test('a move of any size waits for the heartbeat', () {
      expect(
        decide(
          latest: northBy(101, after: const Duration(seconds: 60)),
          toEveryone: first,
        ),
        isNull,
      );
      expect(
        decide(
          latest: northBy(5000, after: const Duration(minutes: 3)),
          toEveryone: first,
        ),
        isNull,
      );
    });

    test('the heartbeat goes to everyone every five minutes', () {
      expect(
        decide(
          latest: northBy(0, after: const Duration(minutes: 5)),
          toEveryone: first,
        ),
        LiveAudience.everyone,
      );
    });

    test('a fix landing just short of five minutes still makes it', () {
      expect(
        decide(
          latest: northBy(0, after: const Duration(minutes: 4, seconds: 40)),
          toEveryone: first,
        ),
        LiveAudience.everyone,
      );
      expect(
        decide(
          latest: northBy(0, after: const Duration(minutes: 4)),
          toEveryone: first,
        ),
        isNull,
      );
    });

    test('the very fix already sent is never resent', () {
      expect(
        decide(
          latest: first.position,
          toEveryone: first,
          watchers: true,
          now: start.add(const Duration(minutes: 6)),
        ),
        isNull,
      );
    });

    test('a clock that moved back makes the next send due, not stuck', () {
      expect(
        decide(
          latest: northBy(5, after: const Duration(seconds: 10)),
          toEveryone: first,
          now: start.subtract(const Duration(minutes: 20)),
        ),
        LiveAudience.everyone,
      );
    });
  });

  group('with watchers', () {
    final first = sent(northBy(0));

    test('a 10 m move five seconds later goes to the watchers', () {
      expect(
        decide(
          latest: northBy(11, after: const Duration(seconds: 5)),
          toEveryone: first,
          watchers: true,
        ),
        LiveAudience.watchers,
      );
    });

    test('a 10 m move within five seconds waits', () {
      expect(
        decide(
          latest: northBy(11, after: const Duration(seconds: 3)),
          toEveryone: first,
          watchers: true,
        ),
        isNull,
      );
    });

    test('indoor jitter inside the uncertainty waits for the 30 s floor', () {
      final indoors = sent(northBy(0, u: 20));

      expect(
        decide(
          latest: northBy(15, after: const Duration(seconds: 6), u: 20),
          toEveryone: indoors,
          watchers: true,
        ),
        isNull,
      );
      expect(
        decide(
          latest: northBy(15, after: const Duration(seconds: 30), u: 20),
          toEveryone: indoors,
          watchers: true,
        ),
        LiveAudience.watchers,
      );
    });

    test('a coarse fix sharpened to at least half goes to the watchers', () {
      final coarse = sent(northBy(0, u: 60));

      expect(
        decide(
          latest: northBy(2, after: const Duration(seconds: 6), u: 30),
          toEveryone: coarse,
          watchers: true,
        ),
        LiveAudience.watchers,
      );
      expect(
        decide(
          latest: northBy(2, after: const Duration(seconds: 6), u: 31),
          toEveryone: coarse,
          watchers: true,
        ),
        isNull,
      );
    });

    test('an already sharp fix getting sharper is not news', () {
      final sharp = sent(northBy(0, u: 8));

      expect(
        decide(
          latest: northBy(1, after: const Duration(seconds: 6), u: 3),
          toEveryone: sharp,
          watchers: true,
        ),
        isNull,
      );
    });

    test('thirty seconds without moving still goes to the watchers', () {
      expect(
        decide(
          latest: northBy(0, after: const Duration(seconds: 30)),
          toEveryone: first,
          watchers: true,
        ),
        LiveAudience.watchers,
      );
    });

    test('the watchers count from whichever send reached them last', () {
      final toWatchers = sent(northBy(10, after: const Duration(seconds: 20)));

      expect(
        decide(
          latest: northBy(12, after: const Duration(seconds: 23)),
          toEveryone: first,
          toWatchers: toWatchers,
          watchers: true,
        ),
        isNull,
      );
      expect(
        decide(
          latest: northBy(21, after: const Duration(seconds: 26)),
          toEveryone: first,
          toWatchers: toWatchers,
          watchers: true,
        ),
        LiveAudience.watchers,
      );
    });

    test('everyone else still gets only the heartbeat', () {
      expect(
        decide(
          latest: northBy(150, after: const Duration(seconds: 61)),
          toEveryone: first,
          toWatchers: sent(northBy(140, after: const Duration(seconds: 55))),
          watchers: true,
        ),
        LiveAudience.watchers,
      );
      expect(
        decide(
          latest: northBy(150, after: const Duration(minutes: 5)),
          toEveryone: first,
          toWatchers: sent(northBy(140, after: const Duration(minutes: 4))),
          watchers: true,
        ),
        LiveAudience.everyone,
      );
    });
  });

  test('capture runs precise only while someone watches', () {
    expect(liveCaptureModeFor(watched: true), LiveLocationMode.precise);
    expect(liveCaptureModeFor(watched: false), LiveLocationMode.coarse);
  });
}
