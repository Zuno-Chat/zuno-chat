import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/connection_monitor.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';

import 'room_page_harness.dart';

void main() {
  late StreamController<ConnectionStatus> status;
  late RoomPageHarness harness;

  setUp(() {
    status = StreamController<ConnectionStatus>.broadcast();
    addTearDown(status.close);
    harness = RoomPageHarness(
      overrides: [
        connectionStatusProvider.overrideWith((ref) => status.stream),
      ],
    );
    harness.room.prev_batch = 'older';
    harness.respond = (request) {
      if (request.url.path.endsWith('/messages')) {
        throw http.ClientException('Failed host lookup');
      }
      return null;
    };
  });

  int historyRequests() =>
      harness.requests.where((path) => path.endsWith('/messages')).length;

  testWidgets('a failed history request is not retried on its own', (
    tester,
  ) async {
    await harness.pumpRoomPage(tester);
    await harness.drive(tester);

    expect(historyRequests(), 1);
  });

  testWidgets('no history is requested while known to be offline', (
    tester,
  ) async {
    await tester.pumpWidget(
      await harness.app(home: RoomPage(room: harness.room)),
    );
    status.add(ConnectionStatus.noInternet);
    await harness.settle(tester);
    await harness.drive(tester);

    expect(historyRequests(), 0);
  });

  testWidgets('history is requested again once back online', (tester) async {
    await harness.pumpRoomPage(tester);
    await harness.drive(tester);
    status.add(ConnectionStatus.noInternet);
    await harness.drive(tester, turns: 2);

    status.add(ConnectionStatus.online);
    await harness.drive(tester);

    expect(historyRequests(), 2);
  });

  testWidgets('history is requested again after a successful sync', (
    tester,
  ) async {
    await harness.pumpRoomPage(tester);
    await harness.drive(tester);

    harness.client.onSync.add(SyncUpdate(nextBatch: 'next'));
    await harness.drive(tester);

    expect(historyRequests(), 2);
  });
}
