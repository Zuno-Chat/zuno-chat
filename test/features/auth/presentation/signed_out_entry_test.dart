import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/device_safety.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/zuno_splash.dart';
import 'package:zuno/features/auth/presentation/signed_out_entry.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  final contacted = <Uri>[];
  var checks = 0;

  setUp(() {
    contacted.clear();
    checks = 0;
    SharedPreferences.setMockInitialValues({});
  });

  MockClient server({Set<String> down = const {}}) =>
      MockClient((request) async {
        contacted.add(request.url);
        if (down.contains(request.url.host)) {
          throw http.ClientException('offline');
        }
        final path = request.url.path;
        if (path.endsWith('/versions')) {
          return http.Response(
            jsonEncode({
              'versions': ['v1.1', 'v1.5'],
            }),
            200,
          );
        }
        if (path.endsWith('/login')) {
          return http.Response(
            jsonEncode({
              'flows': [
                {'type': 'm.login.password'},
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403);
      });

  Future<void> settle(WidgetTester tester) async {
    for (var turn = 0; turn < 40; turn++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpEntry(
    WidgetTester tester, {
    Set<String> down = const {},
    Set<DeviceRisk> risks = const {},
    Future<Set<DeviceRisk>>? pendingCheck,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(
            buildTestClient(httpClient: server(down: down)),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          deviceRisksProvider.overrideWith((ref) {
            checks++;
            return pendingCheck ?? Future.value(risks);
          }),
        ],
        child: const MaterialApp(home: SignedOutEntry()),
      ),
    );
    await settle(tester);
  }

  testWidgets('signs in to zuno.chat without asking for a server', (
    tester,
  ) async {
    await pumpEntry(tester);

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Server'), findsNothing);
  });

  testWidgets('nothing but zuno.chat is contacted until it is changed', (
    tester,
  ) async {
    await pumpEntry(tester);

    expect(contacted, isNotEmpty);
    expect(contacted.every((uri) => uri.host == 'zuno.chat'), isTrue);
  });

  testWidgets('the server can be changed from sign-in', (tester) async {
    await pumpEntry(tester);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    expect(find.text('Server'), findsOneWidget);
  });

  testWidgets('an unreachable zuno.chat offers another try or another server', (
    tester,
  ) async {
    await pumpEntry(tester, down: {'zuno.chat'});

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Use another server'), findsOneWidget);
    expect(find.text('Username'), findsNothing);
  });

  testWidgets('another server signs in while zuno.chat is down', (
    tester,
  ) async {
    await pumpEntry(tester, down: {'zuno.chat'});

    await tester.tap(find.text('Use another server'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'example.org');
    await tester.tap(find.text('Continue'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('example.org'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('an unsafe device is warned before it can sign in', (
    tester,
  ) async {
    await pumpEntry(tester, risks: {DeviceRisk.rooted});

    expect(find.text('This device may not be safe'), findsOneWidget);
    expect(find.text('Username'), findsNothing);
  });

  testWidgets('an unlocked bootloader is warned about before sign-in', (
    tester,
  ) async {
    await pumpEntry(tester, risks: {DeviceRisk.unlockedBootloader});

    expect(find.text('The bootloader is unlocked'), findsOneWidget);
    expect(find.text('Username'), findsNothing);
  });

  testWidgets('continue anyway moves on to sign-in', (tester) async {
    await pumpEntry(tester, risks: {DeviceRisk.rooted});

    await tester.tap(find.text('Continue anyway'));
    await settle(tester);

    expect(find.text('This device may not be safe'), findsNothing);
    expect(find.text('Username'), findsOneWidget);
  });

  testWidgets('an acknowledged warning never returns or re-checks', (
    tester,
  ) async {
    await pumpEntry(tester, risks: {DeviceRisk.rooted});
    await tester.tap(find.text('Continue anyway'));
    await tester.pump();
    checks = 0;

    await pumpEntry(tester, risks: {DeviceRisk.rooted});

    expect(find.text('This device may not be safe'), findsNothing);
    expect(find.text('Username'), findsOneWidget);
    expect(checks, 0);
  });

  testWidgets('the splash holds while the device is being checked', (
    tester,
  ) async {
    await pumpEntry(tester, pendingCheck: Completer<Set<DeviceRisk>>().future);

    expect(find.byType(ZunoSplash), findsOneWidget);
    expect(find.text('Username'), findsNothing);
  });
}
