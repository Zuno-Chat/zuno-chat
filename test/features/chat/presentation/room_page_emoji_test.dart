import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/navigation/chat_route.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/features/chat/presentation/message_composer.dart';
import 'package:zuno/features/chat/presentation/message_list_view.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/chat/presentation/send_icon.dart';
import 'package:zuno_emoji/zuno_emoji.dart';

import '../../../helpers/fake_emoji.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';
import 'room_page_harness.dart';

const _homeIndicator = 34.0;
const _keyboard = 300.0;

void main() {
  late RoomPageHarness harness;

  void phone(WidgetTester tester) {
    tester.view.physicalSize =
        const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
  }

  void keyboard(WidgetTester tester, double inset) {
    final ratio = tester.view.devicePixelRatio;
    tester.view.viewInsets = FakeViewPadding(bottom: inset * ratio);
    tester.view.viewPadding = FakeViewPadding(bottom: _homeIndicator * ratio);
    tester.view.padding = FakeViewPadding(
      bottom: math.max(0, _homeIndicator - inset) * ratio,
    );
  }

  Future<void> openRoom(
    WidgetTester tester, {
    PlatformCapabilities? capabilities,
  }) async {
    phone(tester);
    harness = RoomPageHarness(
      db: SendingFakeDatabaseApi(),
      capabilities: capabilities,
    );
    harness.db.events = [
      for (var i = 0; i < 3; i++)
        harness.message(
          '\$m$i',
          body: 'message $i',
          at: DateTime(2026, 9, 20, 12, i),
        ),
    ];
    keyboard(tester, 0);
    await harness.pumpRoomPageOverLauncher(tester);
  }

  Finder field() => find.descendant(
    of: find.byType(MessageComposer),
    matching: find.byType(TextField),
  );

  TextEditingController text(WidgetTester tester) =>
      tester.widget<TextField>(field()).controller!;

  Finder inPicker(Finder finder) =>
      find.descendant(of: find.byType(EmojiPicker), matching: finder);

  double composerBottom(WidgetTester tester) =>
      tester.getRect(find.byType(MessageComposer)).bottom;

  Future<void> typeWithKeyboard(WidgetTester tester) async {
    await tester.showKeyboard(field());
    keyboard(tester, _keyboard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the smiley swaps the keyboard for the emoji list', (
    tester,
  ) async {
    await openRoom(tester);
    await typeWithKeyboard(tester);
    expect(tester.testTextInput.isVisible, isTrue);

    await showEmojiList(tester);

    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byType(EmojiPicker), findsOneWidget);
    expect(find.byTooltip('Show keyboard'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets(
    'the message box stays put while the keyboard and the list swap',
    (tester) async {
      await openRoom(tester);
      await typeWithKeyboard(tester);
      final bottom = composerBottom(tester);

      await showEmojiList(tester);
      for (final inset in [200.0, 100.0, 20.0, 0.0]) {
        keyboard(tester, inset);
        await tester.pump();
        expect(composerBottom(tester), bottom, reason: 'keyboard at $inset');
      }

      await tester.tap(find.byTooltip('Show keyboard'));
      await tester.pump();
      for (final inset in [20.0, 100.0, 200.0, _keyboard]) {
        keyboard(tester, inset);
        await tester.pump();
        expect(composerBottom(tester), bottom, reason: 'keyboard at $inset');
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(EmojiPicker), findsNothing);
      expect(composerBottom(tester), bottom);
    },
  );

  testWidgets('a tap in the message box brings the keyboard back', (
    tester,
  ) async {
    await openRoom(tester);
    await typeWithKeyboard(tester);
    await showEmojiList(tester);
    keyboard(tester, 0);
    await tester.pump();

    await tester.tap(field());
    keyboard(tester, _keyboard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(EmojiPicker), findsNothing);
    expect(find.byTooltip('Show emoji'), findsOneWidget);
  });

  testWidgets('an emoji goes in at the cursor, replacing a selection', (
    tester,
  ) async {
    await openRoom(tester);
    await tester.enterText(field(), 'abc');
    text(tester).selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 2,
    );
    await showEmojiList(tester);

    await tester.tap(inPicker(find.text('😀')));
    await tester.pump();

    expect(text(tester).text, 'a😀c');
    expect(text(tester).selection, const TextSelection.collapsed(offset: 3));
  });

  testWidgets('an emoji goes at the end when the cursor was never placed', (
    tester,
  ) async {
    await openRoom(tester);
    text(tester).value = const TextEditingValue(text: 'hi');
    await showEmojiList(tester);

    await tester.tap(inPicker(find.text('😀')));
    await tester.pump();

    expect(text(tester).text, 'hi😀');
  });

  testWidgets('a cursor past the end of the text counts as the end', (
    tester,
  ) async {
    await openRoom(tester);
    text(tester).value = const TextEditingValue(
      text: 'hi',
      selection: TextSelection.collapsed(offset: 9),
    );
    await showEmojiList(tester);

    await tester.tap(inPicker(find.text('😀')));
    await tester.pump();
    expect(text(tester).text, 'hi😀');
    await tester.tap(inPicker(find.byTooltip('Delete')));
    await tester.pump();
    expect(text(tester).text, 'hi');
  });

  testWidgets('backspace removes a whole emoji', (tester) async {
    await openRoom(tester);
    const typed = 'a👨‍👩‍👧🇩🇪1️⃣';
    text(tester).value = TextEditingValue(
      text: typed,
      selection: TextSelection.collapsed(offset: typed.length),
    );
    await showEmojiList(tester);

    for (final left in ['a👨‍👩‍👧🇩🇪', 'a👨‍👩‍👧', 'a']) {
      await tester.tap(inPicker(find.byTooltip('Delete')));
      await tester.pump();
      expect(text(tester).text, left);
    }
  });

  testWidgets('Back closes the emoji list before the chat', (tester) async {
    await openRoom(tester);
    await showEmojiList(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(EmojiPicker), findsNothing);
    expect(find.byType(RoomPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await harness.settle(tester);
    expect(find.byType(RoomPage), findsNothing);
  });

  testWidgets('a tap on empty chat space closes the list, a scroll does not', (
    tester,
  ) async {
    await openRoom(tester);
    await showEmojiList(tester);

    await tester.drag(find.byType(MessageListView), const Offset(0, 120));
    await tester.pump();
    expect(find.byType(EmojiPicker), findsOneWidget);

    await tester.tapAt(
      tester.getTopLeft(find.byType(MessageListView)) + const Offset(24, 24),
    );
    await tester.pump();
    expect(find.byType(EmojiPicker), findsNothing);
  });

  testWidgets('sending keeps the list open', (tester) async {
    await openRoom(tester);
    await tester.enterText(field(), 'hello');
    await showEmojiList(tester);

    await tester.tap(find.byType(SendIcon));
    await harness.drive(tester);

    expect(harness.sent.single['body'], 'hello');
    expect(find.byType(EmojiPicker), findsOneWidget);
  });

  testWidgets('search grows out of the list without the chat jumping', (
    tester,
  ) async {
    await openRoom(tester);
    await typeWithKeyboard(tester);
    final bottom = composerBottom(tester);
    await showEmojiList(tester);
    keyboard(tester, 0);
    await tester.pump();

    await tester.tap(inPicker(find.byTooltip('Search emoji')));
    await tester.pump();
    for (final inset in [0.0, 100.0, 200.0, _keyboard]) {
      keyboard(tester, inset);
      await tester.pump();
      expect(
        composerBottom(tester),
        lessThanOrEqualTo(bottom),
        reason: 'keyboard at $inset',
      );
    }
    final search = inPicker(find.byType(TextField));
    await tester.enterText(search, 'grinning');
    await tester.pump();
    final result = inPicker(find.text('😀')).first;
    expect(
      tester.getRect(result).bottom,
      lessThanOrEqualTo(tester.getRect(search).top),
    );
    await tester.tap(result);
    await tester.pump();

    expect(text(tester).text, '😀');
  });

  testWidgets('the list takes the height the keyboard last had', (
    tester,
  ) async {
    await openRoom(tester);
    await tester.showKeyboard(field());
    keyboard(tester, 280);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await showEmojiList(tester);
    keyboard(tester, 0);
    await tester.pump();
    expect(
      tester.getSize(find.byType(EmojiPicker)).height,
      280 - _homeIndicator,
    );
  });

  testWidgets('a hardware keyboard never leaves the list stuck open', (
    tester,
  ) async {
    await openRoom(tester);
    await showEmojiList(tester);

    await tester.tap(find.byTooltip('Show keyboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(EmojiPicker), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(EmojiPicker), findsNothing);
  });

  testWidgets('a slow keyboard does not close the list early', (tester) async {
    await openRoom(tester);
    await typeWithKeyboard(tester);
    final bottom = composerBottom(tester);
    await showEmojiList(tester);
    keyboard(tester, 0);
    await tester.pump();

    await tester.tap(find.byTooltip('Show keyboard'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(EmojiPicker), findsOneWidget);
    expect(composerBottom(tester), bottom);
    for (final inset in [150.0, _keyboard]) {
      keyboard(tester, inset);
      await tester.pump();
      expect(composerBottom(tester), bottom, reason: 'keyboard at $inset');
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EmojiPicker), findsNothing);
    expect(composerBottom(tester), bottom);
  });

  testWidgets('a popup over the list does not bring the keyboard back', (
    tester,
  ) async {
    await openRoom(tester);
    await typeWithKeyboard(tester);
    await showEmojiList(tester);
    keyboard(tester, 0);
    await tester.pump();

    final wave = inPicker(find.text('👋'));
    await tester.scrollUntilVisible(
      wave,
      200,
      scrollable: find
          .descendant(
            of: find.byType(EmojiPicker),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.ensureVisible(wave);
    await harness.settle(tester);
    await tester.longPress(wave);
    await harness.settle(tester);
    await tester.tap(find.text('👋🏽'));
    await harness.settle(tester);

    expect(text(tester).text, '👋🏽');
    expect(find.byType(EmojiPicker), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(MessageComposer),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('a tap in the message box during search ends the search', (
    tester,
  ) async {
    await openRoom(tester);
    await showEmojiList(tester);
    await tester.tap(inPicker(find.byTooltip('Search emoji')));
    await tester.pump();
    keyboard(tester, _keyboard);
    await tester.pump();

    await tester.tap(field());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(EmojiPicker), findsNothing);
    expect(find.byTooltip('Show emoji'), findsOneWidget);
  });

  testWidgets('large text keeps the search strip whole', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openRoom(tester);
    await showEmojiList(tester);

    await tester.tap(inPicker(find.byTooltip('Search emoji')));
    await tester.pump();
    keyboard(tester, _keyboard);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape keeps its own height and leaves room for the chat', (
    tester,
  ) async {
    await openRoom(tester);
    await typeWithKeyboard(tester);
    keyboard(tester, 0);
    await tester.pump();

    final ratio = tester.view.devicePixelRatio;
    tester.view.physicalSize = const Size(844, 390) * ratio;
    await tester.pump();
    await showEmojiList(tester);

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(EmojiPicker)).height,
      390 * 0.45 - _homeIndicator,
    );
    expect(tester.getSize(find.byType(MessageListView)).height, greaterThan(0));
  });

  testWidgets('on iPhone, Back leaves the chat even with the list open', (
    tester,
  ) async {
    await openRoom(tester, capabilities: iosCapabilities);
    await showEmojiList(tester);

    await tester.binding.handlePopRoute();
    await harness.settle(tester);

    expect(find.byType(RoomPage), findsNothing);
  });

  testWidgets('the back arrow leaves the chat at once', (tester) async {
    await openRoom(tester);
    await showEmojiList(tester);

    await tester.tap(find.byType(BackButton));
    await harness.settle(tester);

    expect(find.byType(RoomPage), findsNothing);
  });

  testWidgets(
    'a chat with the list open still lets an earlier chat come back',
    (tester) async {
      await openRoom(tester);
      harness.addChat('!other:example.org', 'Other');
      final navigator = Navigator.of(tester.element(find.byType(RoomPage)));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => RoomPage(
              room: harness.client.getRoomById('!other:example.org')!,
            ),
          ),
        ),
      );
      await harness.settle(tester);
      await showEmojiList(tester);

      expect(returnToChat(navigator, harness.room.id), isTrue);
      await harness.settle(tester);

      expect(find.byType(RoomPage), findsOneWidget);
      expect(
        tester.widget<RoomPage>(find.byType(RoomPage)).room.id,
        harness.room.id,
      );
    },
  );

  testWidgets('closing the keyboard during search goes back to the full list', (
    tester,
  ) async {
    await openRoom(tester);
    await typeWithKeyboard(tester);
    final bottom = composerBottom(tester);
    await showEmojiList(tester);
    keyboard(tester, 0);
    await tester.pump();
    await tester.tap(inPicker(find.byTooltip('Search emoji')));
    await tester.pump();
    keyboard(tester, _keyboard);
    await tester.pump();

    for (final inset in [200.0, 100.0, 0.0]) {
      keyboard(tester, inset);
      await tester.pump();
    }
    await tester.pump();

    expect(inPicker(find.byType(TextField)), findsNothing);
    expect(inPicker(find.byTooltip('Search emoji')), findsOneWidget);
    expect(composerBottom(tester), bottom);
  });

  testWidgets('the list opens on all emoji after a search was left open', (
    tester,
  ) async {
    await openRoom(tester);
    await showEmojiList(tester);
    await tester.tap(inPicker(find.byTooltip('Search emoji')));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();
    await showEmojiList(tester);

    expect(inPicker(find.byType(TextField)), findsNothing);
    expect(inPicker(find.byTooltip('Search emoji')), findsOneWidget);
  });

  testWidgets('leaving search glides down with the keyboard', (tester) async {
    await openRoom(tester);
    await typeWithKeyboard(tester);
    final resting = composerBottom(tester);
    await showEmojiList(tester);
    keyboard(tester, 0);
    await tester.pump();
    await tester.tap(inPicker(find.byTooltip('Search emoji')));
    await tester.pump();
    keyboard(tester, _keyboard);
    await tester.pump();

    var inset = _keyboard;
    var bottom = composerBottom(tester);
    for (final next in [280.0, 240.0, 180.0, 120.0, 60.0, 0.0]) {
      keyboard(tester, next);
      await tester.pump();
      final moved = composerBottom(tester) - bottom;
      expect(moved, inInclusiveRange(0, inset - next + 0.5), reason: '$next');
      inset = next;
      bottom = composerBottom(tester);
    }
    await tester.pump();

    expect(composerBottom(tester), resting);
    expect(inPicker(find.byTooltip('Search emoji')), findsOneWidget);
  });

  testWidgets('the list stays where it was between opens', (tester) async {
    await openRoom(tester);
    await showEmojiList(tester);
    await tester.tap(inPicker(find.byTooltip('Animals and nature')));
    await harness.settle(tester);
    expect(inPicker(find.text('🐵')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(EmojiPicker), findsNothing);
    await showEmojiList(tester);

    expect(inPicker(find.text('🐵')), findsOneWidget);
  });

  testWidgets('turning the phone keeps the search open', (tester) async {
    await openRoom(tester);
    await showEmojiList(tester);
    await tester.tap(inPicker(find.byTooltip('Search emoji')));
    await tester.pump();
    keyboard(tester, _keyboard);
    await tester.pump();

    tester.view.physicalSize =
        const Size(844, 390) * tester.view.devicePixelRatio;
    keyboard(tester, 200);
    await tester.pump();
    await tester.pump();

    expect(inPicker(find.byType(TextField)), findsOneWidget);
  });

  testWidgets('losing the right to post closes the list, so Back leaves', (
    tester,
  ) async {
    await openRoom(tester);
    await showEmojiList(tester);

    harness.blockPosting();
    harness.client.onRoomState.add((
      roomId: harness.room.id,
      state: harness.room.getState(EventTypes.RoomPowerLevels)!,
    ));
    await harness.settle(tester);
    expect(find.byType(MessageComposer), findsNothing);

    await tester.binding.handlePopRoute();
    await harness.settle(tester);

    expect(find.byType(RoomPage), findsNothing);
  });
}
