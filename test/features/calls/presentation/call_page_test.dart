import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/calls/presentation/call_controls.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'zuno/calls',
      'zuno/vibration',
      'flutter.baseflow.com/permissions/methods',
      'dexterous.com/flutter/local_notifications',
      'wakelock_plus',
    ]) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
    room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
  });

  for (final kind in CallKind.values) {
    testWidgets('a $kind call builds before its engine exists, dark, with End '
        'call ready and Back blocked', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-${kind.name}',
        kind: kind,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: zunoLightTheme,
            home: CallPage(session: session),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.byTooltip('End call'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is PopScope && !w.canPop),
        findsOneWidget,
      );
      expect(
        Theme.of(tester.element(find.byType(CallControls))).brightness,
        Brightness.dark,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  }
}
