import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/calls/presentation/call_stage.dart';
import 'package:zuno/features/calls/presentation/call_status_line.dart';
import 'package:zuno/features/calls/presentation/call_status_widgets.dart';

import '../../../helpers/real_fonts.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {double width = 360}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 640);
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        theme: zunoDarkTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  Widget avatar(double radius) =>
      CircleAvatar(key: const ValueKey('avatar'), radius: radius);

  group('the voice stage', () {
    testWidgets('centres the picture, the name and the status', (tester) async {
      await pump(
        tester,
        VoiceCallStage(
          avatarBuilder: avatar,
          name: 'Ann Lindqvist',
          status: CallStatus.calling,
        ),
      );

      for (final finder in [
        find.byKey(const ValueKey('avatar')),
        find.text('Ann Lindqvist'),
        find.text('Calling…'),
      ]) {
        expect(tester.getCenter(finder).dx, closeTo(180, 1));
      }
      expect(
        tester.getTopLeft(find.text('Calling…')).dy,
        greaterThan(tester.getBottomLeft(find.text('Ann Lindqvist')).dy),
      );
    });

    testWidgets('says when the other side is muted or on a weak connection', (
      tester,
    ) async {
      await pump(
        tester,
        VoiceCallStage(
          avatarBuilder: avatar,
          name: 'Ann',
          status: CallStatus.talking,
          talkingSince: DateTime(2026, 9, 20),
          remoteMuted: true,
          remoteWeak: true,
        ),
      );

      expect(find.bySemanticsLabel('Ann is muted'), findsOneWidget);
      expect(find.text('Weak connection'), findsOneWidget);
    });

    testWidgets('a very long name is cut, not overflowed', (tester) async {
      await pump(
        tester,
        VoiceCallStage(
          avatarBuilder: avatar,
          name: 'Bartholomew Maximilian ' * 6,
          status: CallStatus.encrypting,
        ),
        width: 320,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('on a short screen (landscape)', () {
    testWidgets('the name and the status stay in view beside a smaller '
        'picture', (tester) async {
      await pump(
        tester,
        Center(
          child: SizedBox(
            width: 640,
            height: 150,
            child: VoiceCallStage(
              avatarBuilder: avatar,
              name: 'Ann Lindqvist',
              status: CallStatus.encrypting,
              encryptingSince: DateTime(2000),
            ),
          ),
        ),
        width: 640,
      );

      final stage = tester.getRect(find.byType(VoiceCallStage));
      for (final finder in [
        find.text('Ann Lindqvist'),
        find.text('Encrypting…'),
        find.text(EncryptingLabel.hint),
      ]) {
        final rect = tester.getRect(finder);
        expect(rect.top, greaterThanOrEqualTo(stage.top));
        expect(rect.bottom, lessThanOrEqualTo(stage.bottom));
      }
      expect(tester.getSize(find.byKey(const ValueKey('avatar'))).width, 72);
    });
  });

  group('the advice after 8 seconds', () {
    testWidgets('counts from when encrypting began, not from when this '
        'widget appeared', (tester) async {
      var now = DateTime(2026, 9, 20, 12, 0, 6);
      await pump(
        tester,
        VideoCallHeader(
          name: 'Ann',
          status: CallStatus.encrypting,
          encryptingSince: DateTime(2026, 9, 20, 12),
          now: () => now,
        ),
      );
      expect(find.text(EncryptingLabel.hint), findsNothing);

      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(EncryptingLabel.hint), findsOneWidget);
    });

    testWidgets('is never cut short in the header, even at twice the font '
        'size', (tester) async {
      await tester.runAsync(loadRealRoboto);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: zunoDarkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 224,
              child: VideoCallHeader(
                name: 'Ann',
                status: CallStatus.encrypting,
                encryptingSince: DateTime(2000),
              ),
            ),
          ),
        ),
      );

      final hint = tester.widget<Text>(find.text(EncryptingLabel.hint));
      expect(hint.maxLines, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('the video header', () {
    testWidgets('an encrypted call shows the lock, the name and the clock in '
        'one pill', (tester) async {
      await pump(
        tester,
        VideoCallHeader(
          name: 'Ann Lindqvist',
          status: CallStatus.talking,
          talkingSince: DateTime(2026, 9, 20, 12),
          now: () => DateTime(2026, 9, 20, 12, 2, 41),
        ),
      );

      expect(find.text('Ann Lindqvist'), findsOneWidget);
      expect(find.text('02:41'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text(EncryptingLabel.label), findsNothing);
    });

    testWidgets('while encrypting the status has its own block under the '
        'name, and the advice joins it after 8 seconds', (tester) async {
      await pump(
        tester,
        const VideoCallHeader(name: 'Ann', status: CallStatus.encrypting),
      );

      expect(
        tester.getTopLeft(find.text('Encrypting…')).dy,
        greaterThan(tester.getBottomLeft(find.text('Ann')).dy),
      );
      await tester.pump(const Duration(seconds: 8));
      expect(find.text(EncryptingLabel.hint), findsOneWidget);
    });

    testWidgets('a long name never pushes the status out', (tester) async {
      await tester.runAsync(loadRealRoboto);
      await pump(
        tester,
        SizedBox(
          width: 224,
          child: VideoCallHeader(
            name: 'Bartholomew Maximilian ' * 4,
            status: CallStatus.encrypting,
            remoteMuted: true,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final status = tester.getRect(find.text('Encrypting…'));
      expect(status.right, lessThanOrEqualTo(224));
      expect(find.bySemanticsLabel(RegExp('is muted')), findsOneWidget);
    });
  });

  group('the group grid', () {
    Future<List<Rect>> rects(WidgetTester tester, int count) async {
      await pump(
        tester,
        CallGrid(
          tiles: [
            for (var i = 0; i < count; i++)
              ColoredBox(key: ValueKey('tile$i'), color: Colors.grey),
          ],
        ),
      );
      return [
        for (var i = 0; i < count; i++)
          tester.getRect(find.byKey(ValueKey('tile$i'))),
      ];
    }

    testWidgets('four people fill two rows of two, all the same size', (
      tester,
    ) async {
      final tiles = await rects(tester, 4);

      expect(tiles.map((r) => r.size).toSet(), hasLength(1));
      expect(tiles[0].top, tiles[1].top);
      expect(tiles[2].top, greaterThan(tiles[0].bottom));
      expect(tiles[3].right, closeTo(360, 0.5));
      expect(tiles[3].bottom, closeTo(640, 0.5));
    });

    testWidgets('an odd one out keeps the same size, centred', (tester) async {
      final tiles = await rects(tester, 5);

      expect(tiles[4].center.dx, closeTo(180, 0.5));
      expect(tiles[4].height, closeTo(tiles[0].height, 0.5));
      expect(tiles[4].width, closeTo(tiles[0].width, 8));
    });

    testWidgets('six people take three rows', (tester) async {
      final tiles = await rects(tester, 6);

      expect(tiles.map((r) => r.top.round()).toSet(), hasLength(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tile keeps its state when people join or leave around it', (
      tester,
    ) async {
      Widget grid(List<String> ids) =>
          CallGrid(tiles: [for (final id in ids) _Counter(key: ValueKey(id))]);

      await pump(tester, grid(['ann', 'ben', 'you']));
      await tester.tap(find.byKey(const ValueKey('you')));
      await tester.pump();
      expect(find.text('you:1'), findsOneWidget);

      await pump(tester, grid(['ann', 'ben', 'cat', 'you']));
      expect(find.text('you:1'), findsOneWidget);

      await pump(tester, grid(['ben', 'you']));
      expect(find.text('you:1'), findsOneWidget);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _taps++),
    child: Text('${(widget.key! as ValueKey<String>).value}:$_taps'),
  );
}
