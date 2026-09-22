import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/calls/presentation/call_controls.dart';

import '../../../helpers/contrast.dart';

void main() {
  late List<String> pressed;

  Future<void> pump(
    WidgetTester tester, {
    CallKind kind = CallKind.voice,
    bool micMuted = false,
    bool cameraOn = false,
    bool speakerOn = false,
    bool enabled = true,
    bool overVideo = false,
    double width = 360,
  }) async {
    pressed = [];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoDarkTheme,
        home: Scaffold(
          body: Center(
            child: CallControls(
              kind: kind,
              micMuted: micMuted,
              cameraOn: cameraOn,
              speakerOn: speakerOn,
              enabled: enabled,
              overVideo: overVideo,
              onToggleMute: () => pressed.add('mute'),
              onToggleCamera: () => pressed.add('camera'),
              onSwitchCamera: () => pressed.add('flip'),
              onToggleSpeaker: () => pressed.add('speaker'),
              onHangUp: () => pressed.add('end'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a voice call offers mute, video, speaker and end, each named', (
    tester,
  ) async {
    await pump(tester);

    for (final name in [
      'Mute',
      'Switch to video call',
      'Turn speaker on',
      'End call',
    ]) {
      expect(find.byTooltip(name), findsOneWidget, reason: name);
    }
    expect(find.byTooltip('Switch camera'), findsNothing);
  });

  testWidgets('the names follow the state they would change', (tester) async {
    await pump(
      tester,
      kind: CallKind.video,
      micMuted: true,
      cameraOn: true,
      speakerOn: true,
    );

    for (final name in [
      'Unmute',
      'Turn camera off',
      'Switch camera',
      'Turn speaker off',
      'End call',
    ]) {
      expect(find.byTooltip(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('a video call with the camera off offers to turn it on, and no '
      'camera switch', (tester) async {
    await pump(tester, kind: CallKind.video);

    expect(find.byTooltip('Turn camera on'), findsOneWidget);
    expect(find.byTooltip('Switch camera'), findsNothing);
  });

  testWidgets('every button does its own thing', (tester) async {
    await pump(tester, kind: CallKind.video, cameraOn: true);

    for (final name in [
      'Mute',
      'Turn camera off',
      'Switch camera',
      'Turn speaker on',
      'End call',
    ]) {
      await tester.tap(find.byTooltip(name));
    }
    expect(pressed, ['mute', 'camera', 'flip', 'speaker', 'end']);
  });

  testWidgets('while connecting only End call works', (tester) async {
    await pump(tester, kind: CallKind.video, cameraOn: true, enabled: false);

    for (final name in [
      'Mute',
      'Turn camera off',
      'Switch camera',
      'Turn speaker on',
      'End call',
    ]) {
      await tester.tap(find.byTooltip(name), warnIfMissed: false);
    }
    expect(pressed, ['end']);
  });

  testWidgets('five buttons fit a small phone, each at least 48 px', (
    tester,
  ) async {
    await pump(tester, kind: CallKind.video, cameraOn: true, width: 320);

    expect(tester.takeException(), isNull);
    final dock = tester.getRect(find.byType(CallControls));
    expect(dock.left, greaterThanOrEqualTo(0));
    expect(dock.right, lessThanOrEqualTo(320));
    for (final name in ['Mute', 'Switch camera', 'End call']) {
      final size = tester.getSize(find.byTooltip(name));
      expect(size.width, greaterThanOrEqualTo(48), reason: name);
      expect(size.height, greaterThanOrEqualTo(48), reason: name);
    }
  });

  testWidgets('End call is red with a white icon, readable on the dock', (
    tester,
  ) async {
    await pump(tester);

    final end = tester.widget<Material>(
      find.descendant(
        of: find.byTooltip('End call'),
        matching: find.byType(Material),
      ),
    );
    final dock = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(CallControls),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(end.color, callEndColor);
    expect(contrastRatio(onCallActionColor, callEndColor), greaterThan(4.5));
    expect(contrastRatio(callEndColor, dock.color!), greaterThan(3));
    expect(
      contrastRatio(callEndColor, zunoDarkTheme.colorScheme.surface),
      greaterThan(3),
    );
    expect(contrastRatio(onCallActionColor, callAcceptColor), greaterThan(4.5));
    expect(
      contrastRatio(callAcceptColor, zunoDarkTheme.colorScheme.surface),
      greaterThan(3),
    );
  });

  testWidgets('a switched-on button is filled, a switched-off one is quiet, '
      'and both icons read', (tester) async {
    await pump(tester, speakerOn: true);

    Material fill(String tooltip) => tester.widget<Material>(
      find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byType(Material),
      ),
    );
    Icon icon(String tooltip) => tester.widget<Icon>(
      find.descendant(of: find.byTooltip(tooltip), matching: find.byType(Icon)),
    );

    final on = fill('Turn speaker off');
    final off = fill('Mute');
    expect(on.color, isNot(off.color));
    expect(
      contrastRatio(icon('Turn speaker off').color!, on.color!),
      greaterThan(4.5),
    );
    expect(contrastRatio(icon('Mute').color!, off.color!), greaterThan(4.5));
  });

  testWidgets('over video a switched-on and a switched-off button both read', (
    tester,
  ) async {
    await pump(tester, kind: CallKind.video, speakerOn: true, overVideo: true);

    Icon icon(String tooltip) => tester.widget<Icon>(
      find.descendant(of: find.byTooltip(tooltip), matching: find.byType(Icon)),
    );
    Material fill(String tooltip) => tester.widget<Material>(
      find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byType(Material),
      ),
    );
    final quietOnDock = Color.alphaBlend(
      fill('Mute').color!,
      Color.alphaBlend(Colors.black54, Colors.black),
    );
    expect(contrastRatio(icon('Mute').color!, quietOnDock), greaterThan(4.5));
    expect(
      contrastRatio(
        icon('Turn speaker off').color!,
        fill('Turn speaker off').color!,
      ),
      greaterThan(4.5),
    );
  });

  testWidgets('every control is a button to a screen reader, and says when '
      'it is unavailable', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, kind: CallKind.video, cameraOn: true, enabled: false);

    SemanticsNode node(String name) => tester.getSemantics(
      find.descendant(of: find.byTooltip(name), matching: find.byType(InkWell)),
    );

    for (final name in ['Mute', 'Turn camera off', 'Switch camera']) {
      expect(
        node(name),
        matchesSemantics(
          tooltip: name,
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
        reason: name,
      );
    }
    expect(
      node('End call'),
      matchesSemantics(
        tooltip: 'End call',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('pressing and holding End call still ends the call', (
    tester,
  ) async {
    await pump(tester);

    await tester.longPress(find.byTooltip('End call'));
    await tester.pump();

    expect(pressed, ['end']);
  });

  testWidgets('no button costs a clipping layer on every video frame, and '
      'the ripple still stays round', (tester) async {
    await pump(tester, kind: CallKind.video, cameraOn: true, overVideo: true);

    final clipped = find.descendant(
      of: find.byType(CallControls),
      matching: find.byWidgetPredicate(
        (w) => w is Material && w.clipBehavior != Clip.none,
      ),
    );
    expect(clipped, findsNothing);
    for (final well in tester.widgetList<InkWell>(find.byType(InkWell))) {
      expect(well.customBorder, isA<CircleBorder>());
    }
  });
}
