import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';

import 'preferences_container.dart';

Future<ProviderContainer> pumpRoomListPage(
  WidgetTester tester,
  Client client, {
  List<Override> overrides = const [],
  Map<String, Object> stored = const {},
}) async {
  final container = await containerWithPreferences(
    stored,
    overrides: [matrixClientProvider.overrideWithValue(client), ...overrides],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        scaffoldMessengerKey: globalScaffoldMessengerKey,
        home: const RoomListPage(),
      ),
    ),
  );
  return container;
}
