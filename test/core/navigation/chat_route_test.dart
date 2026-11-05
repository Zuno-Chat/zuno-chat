import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/navigation/chat_route.dart';

class _Chat extends StatefulWidget {
  final String roomId;

  const _Chat(this.roomId);

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    markChatRoute(context, widget.roomId);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  late OpenChatObserver observer;
  late NavigatorState navigator;

  setUp(() {
    observer = OpenChatObserver();
    addTearDown(observer.dispose);
  });

  Future<void> pumpApp(WidgetTester tester, {bool observed = true}) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [if (observed) observer],
        home: const SizedBox(),
      ),
    );
    navigator = key.currentState!;
  }

  Route<void> page(Widget child) => MaterialPageRoute(builder: (_) => child);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a chat is open while it is on screen', (tester) async {
    await pumpApp(tester);
    expect(observer.openRoomId, isNull);

    navigator.push(page(const _Chat('!a')));
    await settle(tester);
    expect(observer.openRoomId, '!a');

    navigator.pop();
    await settle(tester);
    expect(observer.openRoomId, isNull);
  });

  testWidgets('a page over a chat keeps the chat open', (tester) async {
    await pumpApp(tester);
    navigator.push(page(const _Chat('!a')));
    await settle(tester);

    navigator.push(page(const SizedBox()));
    await settle(tester);

    expect(observer.openRoomId, '!a');
  });

  testWidgets('leaving a chat opened from another chat goes back to the '
      'first one', (tester) async {
    await pumpApp(tester);
    navigator.push(page(const _Chat('!a')));
    await settle(tester);
    navigator.push(page(const _Chat('!b')));
    await settle(tester);
    expect(observer.openRoomId, '!b');

    navigator.pop();
    await settle(tester);

    expect(observer.openRoomId, '!a');
  });

  testWidgets('a page replaced by a chat opens it', (tester) async {
    await pumpApp(tester);
    navigator.push(page(const SizedBox()));
    await settle(tester);

    navigator.pushReplacement(page(const _Chat('!a')));
    await settle(tester);

    expect(observer.openRoomId, '!a');
  });

  testWidgets('no chat is open while the app is in the background', (
    tester,
  ) async {
    await pumpApp(tester);
    navigator.push(page(const _Chat('!a')));
    await settle(tester);
    var changes = 0;
    observer.addListener(() => changes++);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    expect(observer.openRoomId, isNull);

    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    expect(observer.openRoomId, '!a');
    expect(changes, 2);
  });

  group('returning to a chat', () {
    Finder over() => find.text('over', skipOffstage: false);
    Finder chats() => find.byType(_Chat, skipOffstage: false);

    Future<void> push(WidgetTester tester, Widget child) async {
      navigator.push(page(child));
      await settle(tester);
    }

    testWidgets('closes the pages above it', (tester) async {
      await pumpApp(tester);
      await push(tester, const _Chat('!a'));
      await push(tester, const Text('over'));
      await push(tester, const Text('over'));

      expect(returnToChat(navigator, '!a'), isTrue);
      await settle(tester);

      expect(over(), findsNothing);
      expect(chats(), findsOneWidget);
      expect(observer.openRoomId, '!a');
    });

    testWidgets('leaves a chat on top as it is', (tester) async {
      await pumpApp(tester);
      await push(tester, const _Chat('!a'));

      expect(returnToChat(navigator, '!a'), isTrue);
      await settle(tester);

      expect(chats(), findsOneWidget);
      expect(navigator.canPop(), isTrue);
    });

    testWidgets('goes back to the nearest copy of the chat', (tester) async {
      await pumpApp(tester);
      await push(tester, const _Chat('!a'));
      await push(tester, const Text('over'));
      await push(tester, const _Chat('!a'));
      await push(tester, const Text('over'));

      expect(returnToChat(navigator, '!a'), isTrue);
      await settle(tester);

      expect(over(), findsOneWidget);
      expect(chats(), findsNWidgets(2));
      expect(observer.openRoomId, '!a');
    });

    testWidgets('leaves a page that refuses back open', (tester) async {
      await pumpApp(tester);
      await push(tester, const _Chat('!a'));
      await push(tester, const PopScope(canPop: false, child: Text('over')));

      expect(returnToChat(navigator, '!a'), isFalse);
      await settle(tester);

      expect(over(), findsOneWidget);
    });

    testWidgets('closes a page that refuses back but may close on return', (
      tester,
    ) async {
      await pumpApp(tester);
      await push(tester, const _Chat('!a'));
      final route = page(const PopScope(canPop: false, child: Text('over')));
      markClosableOnReturn(route);
      unawaited(navigator.push(route));
      await settle(tester);

      expect(returnToChat(navigator, '!a'), isTrue);
      await settle(tester);

      expect(over(), findsNothing);
      expect(observer.openRoomId, '!a');
    });

    testWidgets('a chat not in the stack is not returned to', (tester) async {
      await pumpApp(tester);
      await push(tester, const _Chat('!a'));
      await push(tester, const Text('over'));

      expect(returnToChat(navigator, '!b'), isFalse);
      await settle(tester);

      expect(over(), findsOneWidget);
    });

    testWidgets('a navigator that tracks no chats returns to none', (
      tester,
    ) async {
      await pumpApp(tester, observed: false);
      await push(tester, const _Chat('!a'));
      await push(tester, const Text('over'));

      expect(returnToChat(navigator, '!a'), isFalse);
      await settle(tester);

      expect(over(), findsOneWidget);
    });
  });

  test('only a resumed app, or one not yet told, has a chat in front', () {
    expect(chatInFront(null), isTrue);
    expect(chatInFront(AppLifecycleState.resumed), isTrue);
    for (final state in [
      AppLifecycleState.paused,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ]) {
      expect(chatInFront(state), isFalse, reason: state.toString());
    }
  });
}
