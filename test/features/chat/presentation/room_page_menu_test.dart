import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/platform_capabilities.dart';
import 'room_page_harness.dart';

void main() {
  Future<void> openMenu(
    WidgetTester tester,
    PlatformCapabilities capabilities,
  ) async {
    final harness = RoomPageHarness(capabilities: capabilities);
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Android offers to add the chat to the home screen', (
    tester,
  ) async {
    await openMenu(tester, androidCapabilities);

    expect(find.text('Add to home screen'), findsOneWidget);
    expect(find.text('Reload messages'), findsOneWidget);
  });

  testWidgets('without home screen shortcuts the menu does not offer one', (
    tester,
  ) async {
    await openMenu(
      tester,
      capabilitiesLike(androidCapabilities, homeScreenShortcuts: false),
    );

    expect(find.text('Add to home screen'), findsNothing);
    expect(find.text('Reload messages'), findsOneWidget);
  });

  testWidgets('iOS does not offer one either', (tester) async {
    await openMenu(tester, iosCapabilities);

    expect(find.text('Add to home screen'), findsNothing);
    expect(find.text('Reload messages'), findsOneWidget);
  });
}
