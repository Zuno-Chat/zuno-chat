import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/current_position.dart';
import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_availability.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/features/location/presentation/location_share_sheet.dart';

import '../../../helpers/platform_capabilities.dart';

final _fixTime = DateTime.utc(2026, 10, 7, 12);

const _geo = GeoUri(
  latitude: 52.5163,
  longitude: 13.3777,
  uncertaintyMeters: 25,
);

class _Opened {
  Future<LocationShareChoice?>? result;
}

Future<_Opened> _open(
  WidgetTester tester,
  Future<LocationFix> Function() locate, {
  PlatformCapabilities? capabilities,
  LiveLocationAvailability liveLocation = LiveLocationAvailability.unavailable,
  bool inChat = false,
  Size screen = const Size(1080, 2400),
  Future<bool> Function()? runsUnrestricted,
  Future<void> Function()? allowUnrestricted,
}) async {
  final opened = _Opened();
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mapTilesProvider.overrideWith((ref) async => null),
        platformCapabilitiesProvider.overrideWithValue(
          capabilities ?? androidCapabilities,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => opened.result = showLocationShareSheet(
                context,
                find: locate,
                liveLocation: liveLocation,
                inChat: inChat,
                runsUnrestricted: runsUnrestricted ?? () async => true,
                allowUnrestricted: allowUnrestricted ?? () async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('shows the fix and hands it back on send', (tester) async {
    final opened = await _open(
      tester,
      () async => LocationFound(geo: _geo, approximate: false, at: _fixTime),
    );

    expect(find.text('Send location'), findsOneWidget);
    expect(find.textContaining('about 25 m'), findsOneWidget);
    expect(find.textContaining('Approximate'), findsNothing);

    await tester.tap(find.text('Send location'));
    await tester.pumpAndSettle();

    expect(await opened.result, const SendPin(_geo));
    expect(find.text('Share live location'), findsNothing);
  });

  testWidgets('labels a coarse-only fix as approximate', (tester) async {
    await _open(
      tester,
      () async => LocationFound(geo: _geo, approximate: true, at: _fixTime),
    );

    expect(find.textContaining('Approximate location'), findsOneWidget);
    expect(find.text('Send location'), findsOneWidget);
  });

  testWidgets('explains when location services are off', (tester) async {
    final opened = await _open(
      tester,
      () async => const LocationFailed(LocationFailure.servicesOff),
    );

    expect(find.textContaining('Location is off'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('Send location'), findsNothing);

    await tester.tapAt(const Offset(180, 100));
    await tester.pumpAndSettle();
    expect(await opened.result, isNull);
  });

  testWidgets('where Settings cannot open on Location Services, names the way '
      'there instead of offering a button', (tester) async {
    await _open(
      tester,
      () async => const LocationFailed(LocationFailure.servicesOff),
      capabilities: iosCapabilities,
    );

    expect(
      find.text(
        'Location is off. Turn on Location Services in Settings, under '
        'Privacy & Security.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open settings'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('offers a retry after a refusal', (tester) async {
    var attempts = 0;
    await _open(tester, () async {
      attempts++;
      return attempts == 1
          ? const LocationFailed(LocationFailure.denied)
          : LocationFound(geo: _geo, approximate: false, at: _fixTime);
    });

    expect(find.textContaining('Allow location access'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Send location'), findsOneWidget);
  });

  group('live location', () {
    Future<LocationFound> found() async =>
        LocationFound(geo: _geo, approximate: false, at: _fixTime);

    testWidgets('picks a duration and hands back a live share', (tester) async {
      final opened = await _open(
        tester,
        found,
        liveLocation: LiveLocationAvailability.available,
        inChat: true,
      );

      await tester.tap(find.text('Share live location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Everyone in this chat sees'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<LiveLocationDuration>>(
              find.byType(RadioGroup<LiveLocationDuration>),
            )
            .groupValue,
        LiveLocationDuration.quarterHour,
      );

      await tester.tap(find.text('2 hours'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start sharing'));
      await tester.pumpAndSettle();

      expect(
        await opened.result,
        ShareLive(
          LivePosition(geo: _geo, at: _fixTime),
          LiveLocationDuration.twoHours,
        ),
      );
    });

    testWidgets('goes back to the pin without sharing', (tester) async {
      await _open(
        tester,
        found,
        liveLocation: LiveLocationAvailability.available,
      );

      await tester.tap(find.text('Share live location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Everyone in this room sees'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Send location'), findsOneWidget);
    });

    testWidgets('names an approximate fix before sharing it live', (
      tester,
    ) async {
      await _open(
        tester,
        () async => LocationFound(geo: _geo, approximate: true, at: _fixTime),
        liveLocation: LiveLocationAvailability.available,
      );

      await tester.tap(find.text('Share live location'));
      await tester.pumpAndSettle();

      expect(find.text('Your location is approximate.'), findsOneWidget);
    });

    testWidgets('explains why it cannot start', (tester) async {
      for (final (availability, inChat, reason) in [
        (
          LiveLocationAvailability.notAllowed,
          false,
          'A room admin can turn on live location under Permissions.',
        ),
        (
          LiveLocationAvailability.notAllowed,
          true,
          'Live location is not available in this chat.',
        ),
        (
          LiveLocationAvailability.alreadySharing,
          false,
          'You are already sharing your live location here.',
        ),
      ]) {
        await _open(tester, found, liveLocation: availability, inChat: inChat);

        final button = tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text('Share live location'),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        );
        expect(button.onPressed, isNull, reason: reason);
        expect(find.text(reason), findsOneWidget);

        await tester.tapAt(const Offset(180, 100));
        await tester.pumpAndSettle();
      }
    });
  });

  group('keeping live location going', () {
    Future<LocationFix> found() async =>
        LocationFound(geo: _geo, approximate: false, at: _fixTime);

    Future<void> chooseLive(WidgetTester tester) async {
      await tester.tap(find.text('Share live location'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers to let Zuno run unrestricted when Android may pause '
        'it', (tester) async {
      var asked = 0;
      await _open(
        tester,
        found,
        liveLocation: LiveLocationAvailability.available,
        runsUnrestricted: () async => false,
        allowUnrestricted: () async => asked++,
      );

      await chooseLive(tester);
      expect(
        find.text(
          'Android can pause live location while your device sits still.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Let Zuno run unrestricted'));
      await tester.pump();
      expect(asked, 1);
    });

    testWidgets('says nothing once Zuno already runs unrestricted', (
      tester,
    ) async {
      await _open(
        tester,
        found,
        liveLocation: LiveLocationAvailability.available,
        runsUnrestricted: () async => true,
      );

      await chooseLive(tester);

      expect(find.text('Let Zuno run unrestricted'), findsNothing);
    });

    testWidgets('checks again on return from the system dialog', (
      tester,
    ) async {
      var unrestricted = false;
      await _open(
        tester,
        found,
        liveLocation: LiveLocationAvailability.available,
        runsUnrestricted: () async => unrestricted,
      );
      await chooseLive(tester);
      expect(find.text('Let Zuno run unrestricted'), findsOneWidget);

      unrestricted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Let Zuno run unrestricted'), findsNothing);
    });
  });

  group('on a landscape phone', () {
    const landscape = Size(2532, 1170);

    Future<LocationFix> found() async =>
        LocationFound(geo: _geo, approximate: true, at: _fixTime);

    testWidgets('the pin and its actions fit without overflowing', (
      tester,
    ) async {
      await _open(
        tester,
        found,
        liveLocation: LiveLocationAvailability.notAllowed,
        screen: landscape,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Send location').hitTestable(), findsOneWidget);
      expect(find.text('Share live location').hitTestable(), findsOneWidget);
    });

    testWidgets('every duration and Start sharing can be reached', (
      tester,
    ) async {
      final opened = await _open(
        tester,
        found,
        liveLocation: LiveLocationAvailability.available,
        screen: landscape,
      );
      await tester.tap(find.text('Share live location'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Start sharing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start sharing'));
      await tester.pumpAndSettle();

      expect(await opened.result, isA<ShareLive>());
    });
  });
}
