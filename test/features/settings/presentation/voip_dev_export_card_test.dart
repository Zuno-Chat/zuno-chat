import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/voip/voip_channel.dart';
import 'package:zuno/core/security/sensitive_clipboard.dart';
import 'package:zuno/features/settings/presentation/voip_dev_export_card.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, Object?>? export;

  setUp(() {
    ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);
    export = {
      'token': 'a1b2c3d4',
      'kid': 16909060,
      'key': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',
      'environment': 'development',
    };
    messenger.setMockMethodCallHandler(
      voipChannel,
      (call) async => call.method == 'devExport' ? export : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(voipChannel, null));
  });

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: VoipDevExportCard())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a development build shows the token and key id, never the key', (
    tester,
  ) async {
    await pumpCard(tester);

    expect(find.text('Call push test values'), findsOneWidget);
    expect(find.text('a1b2c3d4'), findsOneWidget);
    expect(find.text('16909060'), findsOneWidget);
    expect(
      find.text('AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8='),
      findsNothing,
    );
  });

  testWidgets('copying hands the test tool all three values', (tester) async {
    final native = installFakeCallsChannel();
    await pumpCard(tester);

    await tester.tap(find.text('Copy test values'));
    await tester.pump();

    SensitiveClipboard.instance.cancelPendingClear();
    final copied = native.argsOf('copySensitive').single! as Map;
    expect(jsonDecode(copied['text'] as String), {
      'token': 'a1b2c3d4',
      'kid': 16909060,
      'key': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',
    });
  });

  testWidgets('a production build shows nothing at all', (tester) async {
    export = {...export!, 'environment': 'production'};

    await pumpCard(tester);

    expect(find.text('Call push test values'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('a build with no export shows nothing', (tester) async {
    export = null;

    await pumpCard(tester);

    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('without VoIP rings nothing is asked or shown', (tester) async {
    ambientCapabilities = androidCapabilities;
    var asked = false;
    messenger.setMockMethodCallHandler(voipChannel, (_) async {
      asked = true;
      return export;
    });

    await pumpCard(tester);

    expect(asked, isFalse);
    expect(find.byType(ListTile), findsNothing);
  });
}
