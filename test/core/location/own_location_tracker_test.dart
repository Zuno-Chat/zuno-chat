import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/current_position.dart';
import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/own_location_tracker.dart';

void main() {
  late StreamController<LocationFix> fixes;
  late OwnLocationTracker tracker;
  late int notified;

  LocationFound found(double latitude) => LocationFound(
    geo: GeoUri(latitude: latitude, longitude: 13.4),
    approximate: false,
    at: DateTime.utc(2026, 10, 8, 12),
  );

  setUp(() {
    fixes = StreamController<LocationFix>.broadcast();
    tracker = OwnLocationTracker(watch: () => fixes.stream);
    notified = 0;
    tracker.addListener(() => notified++);
  });

  tearDown(() async {
    tracker.dispose();
    await fixes.close();
  });

  test('locates only while shown and active', () async {
    tracker.show();
    expect(fixes.hasListener, isFalse);

    tracker.active = true;
    expect(fixes.hasListener, isTrue);

    fixes.add(found(52.5));
    await pumpEventQueue();
    expect(tracker.fix, found(52.5));
  });

  test('pauses while inactive, keeping the last fix, and resumes', () async {
    tracker
      ..active = true
      ..show();
    fixes.add(found(52.5));
    await pumpEventQueue();

    tracker.active = false;
    expect(fixes.hasListener, isFalse);
    expect(tracker.fix, found(52.5));

    tracker.active = true;
    expect(fixes.hasListener, isTrue);
  });

  test('hiding stops locating and forgets the fix', () async {
    tracker
      ..active = true
      ..show();
    fixes.add(found(52.5));
    await pumpEventQueue();

    tracker.hide();

    expect(fixes.hasListener, isFalse);
    expect(tracker.fix, isNull);
    expect(tracker.showing, isFalse);
  });

  test('a failure hides it and says why', () async {
    final failures = <LocationFailure>[];
    tracker.failures.listen(failures.add);
    tracker
      ..active = true
      ..show();

    fixes.add(const LocationFailed(LocationFailure.denied));
    await pumpEventQueue();

    expect(failures, [LocationFailure.denied]);
    expect(tracker.showing, isFalse);
    expect(fixes.hasListener, isFalse);
  });

  test('tells its listeners about every change', () async {
    tracker
      ..active = true
      ..show();
    fixes.add(found(52.5));
    await pumpEventQueue();
    tracker.hide();

    expect(notified, 3);
  });
}
