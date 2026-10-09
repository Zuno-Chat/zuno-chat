import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/location_message.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  const geo = GeoUri(
    latitude: 52.5163,
    longitude: 13.3777,
    uncertaintyMeters: 25,
  );

  group('reading a pin', () {
    late Room room;

    setUp(() {
      room = buildTestRoom(buildTestClient(userId: '@me:x'));
    });

    Event event(Map<String, Object?> content) => buildTestEvent(
      room,
      eventId: r'$e',
      senderId: '@a:x',
      content: content,
    );

    test('reads back a pin as this app sends it', () {
      final uri = geo.toUriString();
      final pin = locationOf(
        event({
          'msgtype': MessageTypes.Location,
          'body': 'Location: ${geo.coordinatesLabel}',
          'geo_uri': uri,
          'org.matrix.msc3488.ts': 1700000000000,
          'org.matrix.msc3488.location': {'uri': uri},
          'org.matrix.msc3488.asset': {'type': 'm.self'},
        }),
      );

      expect(pin, geo);
    });

    test('reads a pin that only carries the bare geo_uri', () {
      final pin = locationOf(
        event({
          'msgtype': MessageTypes.Location,
          'body': 'Somewhere',
          'geo_uri': 'geo:1.5,2.5',
        }),
      );

      expect(pin, const GeoUri(latitude: 1.5, longitude: 2.5));
    });

    test(
      'falls back to the MSC3488 location block when geo_uri is missing',
      () {
        final pin = locationOf(
          event({
            'msgtype': MessageTypes.Location,
            'body': 'Somewhere',
            'org.matrix.msc3488.location': {'uri': 'geo:3,4'},
          }),
        );

        expect(pin, const GeoUri(latitude: 3, longitude: 4));
      },
    );

    test('is null for a non-location message', () {
      final pin = locationOf(
        event({'msgtype': MessageTypes.Text, 'body': 'geo:1,2'}),
      );

      expect(pin, isNull);
    });

    test('is null when the geo_uri is malformed', () {
      final pin = locationOf(
        event({
          'msgtype': MessageTypes.Location,
          'body': 'Somewhere',
          'geo_uri': 'geo:north,west',
        }),
      );

      expect(pin, isNull);
    });
  });
}
