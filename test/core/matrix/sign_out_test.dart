import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_sharing.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/sign_out.dart';

import '../../helpers/fake_call_session.dart';
import '../../helpers/fake_live_location.dart';
import '../../helpers/fake_matrix.dart';

class _SdkLogoutClient extends Client {
  _SdkLogoutClient() : super('test', database: FakeDatabaseApi()) {
    setUserId('@me:x');
  }

  final journal = <String>[];
  Object? serverError;

  @override
  Future<void> logout() async {
    try {
      final error = serverError;
      if (error != null) throw error;
      journal.add('server signed out');
    } finally {
      journal.add('cleared');
    }
  }
}

void main() {
  late LiveLocationTestClient client;
  late LiveLocationSharing sharing;

  setUp(() {
    client = LiveLocationTestClient();
    client.rooms.add(LiveLocationTestRoom(id: '!family:x', client: client));
    sharing = LiveLocationSharing(
      client: client,
      capture: FakeLiveLocationCapture(),
      isOffline: () => false,
      recipients: (_) async => const <DeviceKeys>[],
    );
  });

  tearDown(() => sharing.dispose());

  Future<void> startSharing() => sharing.start(
    client.getRoomById('!family:x')!,
    LiveLocationDuration.hour,
    LivePosition(geo: const GeoUri(latitude: 1, longitude: 2), at: clock.now()),
  );

  test('signs out even when a share cannot be cleared', () async {
    await startSharing();
    client.stateWriteError = MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': 'no',
    });

    await signOutThisDevice(
      client,
      windDown: () =>
          windDownBeforeSignOut(activeCall: null, liveLocation: sharing),
      stopDelivery: (_) async {},
    );

    expect(client.journal.last, 'logged out');
  });

  test('ends the call first, as the user\'s own choice, then clears shares '
      'and stops delivery before signing out', () async {
    await startSharing();

    await signOutThisDevice(
      client,
      windDown: () => windDownBeforeSignOut(
        activeCall: FakeCallSession(
          room: buildCallRoom(),
          kind: CallKind.voice,
          journal: client.journal,
        ),
        liveLocation: sharing,
      ),
      stopDelivery: (_) async => client.journal.add('delivery stopped'),
    );

    expect(client.journal, [
      'share published',
      'call ended',
      'share cleared',
      'delivery stopped',
      'logged out',
    ]);
  });

  test('the wind-down looks at the call and the shares when it runs, not '
      'when it is handed out', () async {
    final container = ProviderContainer(
      overrides: [liveLocationSharingProvider.overrideWithValue(sharing)],
    );
    addTearDown(container.dispose);
    final windDown = container.read(signOutWindDownProvider);

    container
        .read(activeCallProvider.notifier)
        .set(
          FakeCallSession(
            room: buildCallRoom(),
            kind: CallKind.voice,
            journal: client.journal,
          ),
        );
    await startSharing();
    await windDown();

    expect(client.journal, ['share published', 'call ended', 'share cleared']);
  });

  test('a sign-out the server never hears of still signs this device out, '
      'as the SDK clears it anyway', () async {
    final signingOut = _SdkLogoutClient()
      ..serverError = MatrixException.fromJson({
        'errcode': 'M_UNKNOWN',
        'error': 'bad gateway',
      });

    await signOutThisDevice(
      signingOut,
      windDown: () async {},
      stopDelivery: (_) async {},
    );

    expect(signingOut.journal, ['cleared']);
  });

  testWidgets('offline, a screen\'s sign-out ends nothing, signs nothing '
      'out, and says to connect first', (tester) async {
    final signingOut = _SdkLogoutClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(signingOut),
          isOfflineProvider.overrideWithValue(const AsyncData(true)),
          signOutWindDownProvider.overrideWithValue(
            () async => signingOut.journal.add('wound down'),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => signOutThisDeviceOrExplain(context, ref),
                child: const Text('Sign out'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sign out'));
    await tester.pump();

    expect(signingOut.journal, isEmpty);
    expect(
      find.text('Not signed out. Check your connection and try again.'),
      findsOneWidget,
    );
  });
}
