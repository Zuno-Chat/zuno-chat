import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/linked_sign_in.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/sign_in_another_device_page.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();
  }

  Future<void> leave(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  http.Response passwordChallenge() => http.Response(
    jsonEncode({
      'session': 's1',
      'flows': [
        {
          'stages': ['m.login.password'],
        },
      ],
      'params': <String, Object?>{},
    }),
    401,
  );

  http.Response issued({int expiresInMs = 300000}) => http.Response(
    jsonEncode({'login_token': 'syl_abcdefgh', 'expires_in_ms': expiresInMs}),
    200,
  );

  Client serverThat(
    http.Response Function(Map<String, Object?> body) answer, {
    List<Map<String, Object?>>? bodies,
  }) {
    return buildTestClient(
        userId: '@alice:example.org',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          bodies?.add(body);
          return answer(body);
        }),
      )
      ..homeserver = Uri.parse('https://example.org')
      ..accessToken = 'syt_token';
  }

  Client serverWantingPassword({
    int expiresInMs = 300000,
    List<Map<String, Object?>>? bodies,
  }) => serverThat(
    (body) => body['auth'] == null
        ? passwordChallenge()
        : issued(expiresInMs: expiresInMs),
    bodies: bodies,
  );

  Future<void> pumpPage(
    WidgetTester tester, {
    required Client client,
    DateTime Function()? now,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold()),
      ),
    );
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => SignInAnotherDevicePage(now: now ?? DateTime.now),
            ),
          ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  Future<void> confirmPassword(WidgetTester tester) async {
    await tester.enterText(field('Password'), 'correct horse battery staple');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await settle(tester);
    await settle(tester);
  }

  List<bool> recordScreenshotBlocking(WidgetTester tester) {
    const channel = MethodChannel('zuno/calls');
    final calls = <bool>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setPreventScreenshots') {
        calls.add((call.arguments as Map)['enabled'] as bool);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return calls;
  }

  Finder qrImage() =>
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is QrPainter);

  testWidgets('asks for the password, then shows the code as QR and text', (
    tester,
  ) async {
    final bodies = <Map<String, Object?>>[];
    await pumpPage(tester, client: serverWantingPassword(bodies: bodies));

    expect(find.text('Confirm your password'), findsOneWidget);
    expect(qrImage(), findsNothing);

    await confirmPassword(tester);

    expect(qrImage(), findsOneWidget);
    expect(find.text(groupedSignInCode('syl_abcdefgh')), findsOneWidget);
    expect(find.textContaining('Expires in'), findsOneWidget);
    expect(bodies, hasLength(2));
    expect((bodies.last['auth'] as Map)['type'], 'm.login.password');
    await leave(tester);
  });

  testWidgets('the countdown ticks without repainting the QR code', (
    tester,
  ) async {
    var clock = DateTime(2026, 9, 22, 12);
    await pumpPage(tester, client: serverWantingPassword(), now: () => clock);
    await confirmPassword(tester);
    final painter = tester.widget<CustomPaint>(qrImage()).painter;
    expect(find.text('Expires in 5:00'), findsOneWidget);

    clock = clock.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Expires in 4:59'), findsOneWidget);
    expect(tester.widget<CustomPaint>(qrImage()).painter, same(painter));
    await leave(tester);
  });

  testWidgets('cancelling the password prompt leaves the page', (tester) async {
    await pumpPage(tester, client: serverWantingPassword());

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.byType(SignInAnotherDevicePage), findsNothing);
    await leave(tester);
  });

  testWidgets('says when the code has expired and makes a new one on request', (
    tester,
  ) async {
    var clock = DateTime(2026, 9, 22, 12);
    final bodies = <Map<String, Object?>>[];
    await pumpPage(
      tester,
      client: serverWantingPassword(expiresInMs: 1500, bodies: bodies),
      now: () => clock,
    );
    await confirmPassword(tester);
    expect(find.text('Expires in 0:01'), findsOneWidget);

    clock = clock.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('This code has expired.'), findsOneWidget);
    expect(qrImage(), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'New code'));
    await settle(tester);
    await confirmPassword(tester);

    expect(qrImage(), findsOneWidget);
    expect(bodies, hasLength(4));
    await leave(tester);
  });

  testWidgets('a server that cannot make codes says so', (tester) async {
    await pumpPage(
      tester,
      client: serverThat(
        (_) => http.Response(
          jsonEncode({
            'errcode': 'M_UNRECOGNIZED',
            'error': 'Unrecognized request',
          }),
          404,
        ),
      ),
    );

    expect(find.text(signInCodesUnsupportedMessage), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('blocks screenshots while open and lifts the block on leaving '
      'when the preference is off', (tester) async {
    final calls = recordScreenshotBlocking(tester);
    await pumpPage(
      tester,
      client: serverWantingPassword(),
      prefs: {'settings.prevent_screenshots': false},
    );
    await confirmPassword(tester);

    expect(calls, [true]);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(calls, [true, false]);
    await leave(tester);
  });

  testWidgets(
    'keeps screenshots blocked on leaving when the preference is on',
    (tester) async {
      final calls = recordScreenshotBlocking(tester);
      await pumpPage(tester, client: serverWantingPassword());
      await confirmPassword(tester);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(calls, [true, true]);
      await leave(tester);
    },
  );
}
