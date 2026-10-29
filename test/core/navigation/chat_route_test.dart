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

  Future<void> pumpApp(WidgetTester tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [observer],
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
