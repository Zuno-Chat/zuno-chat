import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/core/matrix/sync_coordinator.dart';
import 'package:zuno/core/matrix/sync_coordinator_provider.dart';
import 'package:zuno/core/matrix/sync_request_canceller.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../helpers/app_lifecycle.dart';
import '../../helpers/fake_call_session.dart';
import '../../helpers/fake_live_location.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';
import '../../helpers/preferences_container.dart';

class _IdleClient extends Client {
  _IdleClient() : super('idle', database: FakeDatabaseApi());

  @override
  bool isLogged() => true;

  @override
  Future<void> oneShotSync({Duration? timeout}) => Completer<void>().future;
}

void main() {
  late SyncCoordinator sync;
  late LiveLocationHarness live;
  late StreamController<bool> network;

  Future<ProviderContainer> wire({NotificationDeliveryMode? delivery}) async {
    live = LiveLocationHarness();
    network = StreamController<bool>.broadcast();
    addTearDown(network.close);
    sync = SyncCoordinator(_IdleClient(), SyncRequestCanceller(http.Client()));
    addTearDown(sync.dispose);
    final container = await containerWithPreferences(
      {
        if (delivery != null)
          'settings.notification_delivery_mode': delivery.name,
      },
      overrides: [
        ...live.overrides,
        syncCoordinatorProvider.overrideWithValue(sync),
        networkAvailabilityProvider.overrideWithValue(network.stream),
      ],
    );
    container.listen(syncReasonsProvider, (_, _) {});
    return container;
  }

  testWidgets('the foreground follows the app lifecycle', (tester) async {
    moveLifecycleTo(tester.binding, AppLifecycleState.resumed);
    await wire();
    expect(sync.reasons, contains(SyncReason.foreground));

    moveLifecycleTo(tester.binding, AppLifecycleState.paused);
    expect(sync.reasons, isNot(contains(SyncReason.foreground)));

    moveLifecycleTo(tester.binding, AppLifecycleState.resumed);
    expect(sync.reasons, contains(SyncReason.foreground));
  });

  testWidgets('a call holds its reason while it lasts', (tester) async {
    final container = await wire();
    final calls = container.read(activeCallProvider.notifier);

    calls.set(FakeCallSession(room: live.room, kind: CallKind.voice));
    expect(sync.reasons, contains(SyncReason.call));

    calls.set(null);
    expect(sync.reasons, isNot(contains(SyncReason.call)));
  });

  testWidgets('a ring holds its reason while it shows', (tester) async {
    await wire();
    addTearDown(() => SystemRing.instance.clear('call1'));

    SystemRing.instance.set(roomId: live.room.id, callId: 'call1');
    expect(sync.reasons, contains(SyncReason.ring));

    SystemRing.instance.clear('call1');
    expect(sync.reasons, isNot(contains(SyncReason.ring)));
  });

  testWidgets('a live share holds its reason while it runs', (tester) async {
    await wire();
    expect(sync.reasons, isNot(contains(SyncReason.liveShare)));

    await tester.runAsync(
      () => live.sharing.start(
        live.room,
        LiveLocationDuration.hour,
        LivePosition(
          geo: const GeoUri(latitude: 1, longitude: 2),
          at: DateTime.now(),
        ),
      ),
    );

    expect(sync.reasons, contains(SyncReason.liveShare));
  });

  testWidgets('background-service delivery holds its reason, other delivery '
      'does not', (tester) async {
    ambientCapabilities = androidCapabilities;
    await wire(delivery: NotificationDeliveryMode.backgroundService);
    expect(sync.reasons, contains(SyncReason.delivery));

    await wire(delivery: NotificationDeliveryMode.fcm);
    expect(sync.reasons, isNot(contains(SyncReason.delivery)));
  });

  testWidgets('the device network reaches the coordinator', (tester) async {
    ambientCapabilities = androidCapabilities;
    moveLifecycleTo(tester.binding, AppLifecycleState.paused);
    await wire(delivery: NotificationDeliveryMode.backgroundService);
    expect(sync.mode, SyncMode.background);

    network.add(false);
    await tester.pump();
    expect(sync.mode, SyncMode.off);

    network.add(true);
    await tester.pump();
    expect(sync.mode, SyncMode.background);
  });
}
