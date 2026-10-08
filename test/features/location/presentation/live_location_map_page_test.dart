import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/features/location/presentation/live_location_map_page.dart';

import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_geolocator.dart';
import '../../../helpers/fake_live_location.dart';

void main() {
  late LiveLocationHarness harness;

  setUp(() {
    harness = LiveLocationHarness();
    setSelfSignedTestDevices(harness.client, '@alex:x', ['PHONE']);
    setSelfSignedTestDevices(harness.client, '@bea:x', ['TABLET']);
    harness.member('@alex:x', 'Alex');
    harness.member('@bea:x', 'Bea');
  });

  tearDown(() => harness.dispose());

  Future<void> pumpMap(WidgetTester tester, {String? focus}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          home: LiveLocationMapPage(room: harness.room, focus: focus),
        ),
      ),
    );
    await tester.pump();
  }

  MapCamera cameraOf(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;

  double metersFrom(WidgetTester tester, GeoUri geo) => const Distance().as(
    LengthUnit.Meter,
    cameraOf(tester).center,
    LatLng(geo.latitude, geo.longitude),
  );

  Future<void> settleCamera(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  MapOptions optionsOf(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options;

  LatLngBounds regionOf(WidgetTester tester) =>
      (optionsOf(tester).cameraConstraint as ContainCameraCenter).bounds;

  Future<void> zoomAllTheWayOut(WidgetTester tester) async {
    tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!
        .move(regionOf(tester).center, optionsOf(tester).minZoom!);
    await tester.pump();
  }

  bool inView(WidgetTester tester, GeoUri geo) =>
      cameraOf(tester).visibleBounds
          .contains(LatLng(geo.latitude, geo.longitude));

  testWidgets('lists everyone who shares with how fresh they are', (
    tester,
  ) async {
    harness.shareFrom('@alex:x');
    harness.shareFrom('@bea:x', deviceId: 'TABLET');
    harness.positionFrom('@alex:x', deviceId: 'PHONE');
    await tester.pump();

    await pumpMap(tester);

    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Bea'), findsOneWidget);
    expect(find.textContaining('updated just now'), findsOneWidget);
    expect(find.textContaining('waiting for location'), findsOneWidget);
    expect(find.byTooltip('Open in maps app'), findsOneWidget);
  });

  testWidgets('offers Stop on this device\'s own row', (tester) async {
    await harness.startSharing();

    await pumpMap(tester);
    expect(find.text('You'), findsOneWidget);

    await tester.tap(find.text('Stop sharing'));
    await tester.pump();

    expect(harness.sharing.shares.value, isEmpty);
    expect(
      find.text('Nobody is sharing live location here right now.'),
      findsOneWidget,
    );
  });

  testWidgets('watches the room while open', (tester) async {
    harness.shareFrom('@bea:x', deviceId: 'TABLET');

    await pumpMap(tester);

    expect(
      harness.client.toDevice.where((m) => m.type == liveLocationWatchType),
      hasLength(1),
    );
  });

  group('camera', () {
    const berlin = GeoUri(latitude: 52.52, longitude: 13.405);
    const munich = GeoUri(latitude: 48.137, longitude: 11.575);
    const berlinNorth = GeoUri(latitude: 52.574, longitude: 13.405);

    void bothShare() {
      harness.shareFrom('@alex:x');
      harness.shareFrom('@bea:x', deviceId: 'TABLET');
      final earlier = DateTime.now().subtract(const Duration(seconds: 30));
      harness.positionFrom(
        '@alex:x',
        deviceId: 'PHONE',
        geo: berlin,
        at: earlier,
      );
      harness.positionFrom(
        '@bea:x',
        deviceId: 'TABLET',
        geo: munich,
        at: earlier,
      );
    }

    testWidgets('zooms out far enough to see everyone sharing', (tester) async {
      bothShare();
      await tester.pump();
      await pumpMap(tester);

      await zoomAllTheWayOut(tester);

      expect(inView(tester, berlin), isTrue);
      expect(inView(tester, munich), isTrue);
    });

    testWidgets('a lone sharer keeps the map at city scale', (tester) async {
      harness.shareFrom('@bea:x', deviceId: 'TABLET');
      harness.positionFrom('@bea:x', deviceId: 'TABLET', geo: berlin);
      await tester.pump();
      await pumpMap(tester);

      expect(optionsOf(tester).minZoom, 12);
    });

    testWidgets('pans no further than the people sharing', (tester) async {
      bothShare();
      await tester.pump();
      await pumpMap(tester);

      tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!
          .move(const LatLng(40.4168, -3.7038), 10);
      await tester.pump();

      expect(regionOf(tester).contains(cameraOf(tester).center), isTrue);
    });

    testWidgets('waits for a first location before showing a map', (
      tester,
    ) async {
      harness.shareFrom('@bea:x', deviceId: 'TABLET');

      await pumpMap(tester);

      expect(find.text('Waiting for location'), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('opens on the person it was asked to show', (tester) async {
      bothShare();
      await tester.pump();

      await pumpMap(tester, focus: '@bea:x');

      expect(metersFrom(tester, munich), lessThan(1));
      expect(cameraOf(tester).zoom, 16);
    });

    testWidgets('follows that person as they move', (tester) async {
      bothShare();
      await tester.pump();
      await pumpMap(tester, focus: '@alex:x');

      harness.positionFrom('@alex:x', deviceId: 'PHONE', geo: berlinNorth);
      await settleCamera(tester);

      expect(metersFrom(tester, berlinNorth), lessThan(1));
    });

    testWidgets('stops following once the map is dragged', (tester) async {
      bothShare();
      await tester.pump();
      await pumpMap(tester, focus: '@alex:x');

      await tester.drag(find.byType(FlutterMap), const Offset(0, 120));
      await tester.pump(const Duration(seconds: 1));
      final dragged = cameraOf(tester).center;
      harness.positionFrom('@alex:x', deviceId: 'PHONE', geo: berlinNorth);
      await settleCamera(tester);

      expect(cameraOf(tester).center, dragged);
    });

    testWidgets('a tap in the list goes to that person and follows again', (
      tester,
    ) async {
      bothShare();
      await tester.pump();
      await pumpMap(tester, focus: '@alex:x');
      await tester.drag(find.byType(FlutterMap), const Offset(0, 120));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Bea'));
      await settleCamera(tester);
      expect(metersFrom(tester, munich), lessThan(1));

      const munichEast = GeoUri(latitude: 48.137, longitude: 11.6);
      harness.positionFrom('@bea:x', deviceId: 'TABLET', geo: munichEast);
      await settleCamera(tester);
      expect(metersFrom(tester, munichEast), lessThan(1));
    });
  });

  group('updating', () {
    testWidgets('a stale sharer shows as updating until a fresh fix lands', (
      tester,
    ) async {
      harness.shareFrom('@bea:x', deviceId: 'TABLET');
      harness.positionFrom(
        '@bea:x',
        deviceId: 'TABLET',
        at: DateTime.now().subtract(const Duration(minutes: 4, seconds: 30)),
      );
      await tester.pump();

      await pumpMap(tester);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.textContaining('updating, last updated 4 min ago'),
        findsOneWidget,
      );

      harness.positionFrom('@bea:x', deviceId: 'TABLET');
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('updated just now'), findsOneWidget);
    });

    testWidgets('a sharer already fresh shows no updating', (tester) async {
      harness.shareFrom('@bea:x', deviceId: 'TABLET');
      harness.positionFrom('@bea:x', deviceId: 'TABLET');
      await tester.pump();

      await pumpMap(tester);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('your own location', () {
    late FakeGeolocator geolocator;
    const berlin = GeoUri(latitude: 52.52, longitude: 13.405);
    const munich = GeoUri(latitude: 48.137, longitude: 11.575);

    setUp(() {
      geolocator = FakeGeolocator();
      final original = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = geolocator;
      addTearDown(() => GeolocatorPlatform.instance = original);
    });

    Future<void> beaShares() async {
      harness.shareFrom('@bea:x', deviceId: 'TABLET');
      harness.positionFrom('@bea:x', deviceId: 'TABLET', geo: berlin);
    }

    int markers(WidgetTester tester) =>
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length;

    Future<void> showMine(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Show your location'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a watcher sees it on the map, and it goes nowhere', (
      tester,
    ) async {
      await beaShares();
      await tester.pump();
      await pumpMap(tester);
      expect(markers(tester), 1);

      await showMine(tester);
      expect(geolocator.streaming, isTrue);
      geolocator.positions.add(
        fakePosition(latitude: munich.latitude, longitude: munich.longitude),
      );
      await settleCamera(tester);

      expect(markers(tester), 2);
      expect(metersFrom(tester, munich), lessThan(1));
      expect(find.byTooltip('Hide your location'), findsOneWidget);
      expect(
        harness.client.toDevice.where(
          (m) => m.type == liveLocationPositionType,
        ),
        isEmpty,
      );
      expect(harness.client.stateWrites, isEmpty);
      expect(harness.room.sent, isEmpty);
      expect(harness.capture.calls, isEmpty);
    });

    testWidgets('a far-away location of yours fits in the zoom-out too', (
      tester,
    ) async {
      await beaShares();
      await tester.pump();
      await pumpMap(tester);
      await showMine(tester);
      geolocator.positions.add(
        fakePosition(latitude: munich.latitude, longitude: munich.longitude),
      );
      await settleCamera(tester);

      await zoomAllTheWayOut(tester);

      expect(inView(tester, berlin), isTrue);
      expect(inView(tester, munich), isTrue);
    });

    testWidgets('hiding it stops the updates and removes the dot', (
      tester,
    ) async {
      await beaShares();
      await tester.pump();
      await pumpMap(tester);
      await showMine(tester);
      geolocator.positions.add(fakePosition());
      await settleCamera(tester);

      await tester.tap(find.byTooltip('Hide your location'));
      await tester.pump();

      expect(geolocator.streaming, isFalse);
      expect(markers(tester), 1);
    });

    testWidgets('pauses while another screen covers the map', (tester) async {
      await beaShares();
      await tester.pump();
      await pumpMap(tester);
      await showMine(tester);

      Navigator.of(tester.element(find.byType(LiveLocationMapPage))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering')),
        ),
      );
      await tester.pumpAndSettle();
      expect(geolocator.streaming, isFalse);

      Navigator.of(tester.element(find.text('Covering'))).pop();
      await tester.pumpAndSettle();
      expect(geolocator.streaming, isTrue);
    });

    testWidgets('a refusal says why and leaves it off', (tester) async {
      geolocator
        ..permission = LocationPermission.denied
        ..afterRequest = LocationPermission.denied;
      await beaShares();
      await tester.pump();
      await pumpMap(tester);

      await showMine(tester);

      expect(
        find.text('Allow location access to see where you are.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Show your location'), findsOneWidget);
      expect(geolocator.streaming, isFalse);
    });

    testWidgets('is not offered while this device shares here', (tester) async {
      await harness.startSharing();

      await pumpMap(tester);

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byTooltip('Show your location'), findsNothing);
    });
  });
}
