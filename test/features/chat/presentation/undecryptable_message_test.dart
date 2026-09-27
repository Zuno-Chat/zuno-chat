import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/features/chat/presentation/undecryptable_message.dart';
import 'package:zuno/features/verification/presentation/approve_this_device_page.dart';

import '../../../helpers/fake_matrix.dart';

AccountSecurityFacts _facts({required bool backup, required bool usableHere}) =>
    AccountSecurityFacts(
      recoveryExists: true,
      thisDeviceHasIdentityKeys: usableHere,
      keyBackupExists: backup,
      keyBackupUsableHere: usableHere,
      unapprovedOtherDevices: 0,
    );

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    AccountSecurityFacts? facts,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        matrixClientProvider.overrideWithValue(
          buildTestClient(userId: '@me:example.org'),
        ),
        accountSecurityFactsProvider.overrideWith(
          (ref) => facts == null ? const Stream.empty() : Stream.value(facts),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );

  group('in a chat', () {
    testWidgets('a backup this device cannot open yet offers the unlock', (
      tester,
    ) async {
      await pump(
        tester,
        const UndecryptableMessageContent(),
        facts: _facts(backup: true, usableHere: false),
      );
      await tester.pump();

      expect(find.text('Sent before this device signed in.'), findsOneWidget);

      await tester.tap(find.text('Unlock older messages'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ApproveThisDevicePage), findsOneWidget);
    });

    testWidgets('without a backup blames the missing key, and offers '
        'nothing', (tester) async {
      await pump(
        tester,
        const UndecryptableMessageContent(),
        facts: _facts(backup: false, usableHere: false),
      );
      await tester.pump();

      expect(
        find.text(
          "The sender's device did not share the key for this message.",
        ),
        findsOneWidget,
      );
      expect(find.text('Unlock older messages'), findsNothing);
    });

    testWidgets('while the facts load it offers nothing', (tester) async {
      await pump(tester, const UndecryptableMessageContent());

      expect(find.textContaining('did not share the key'), findsOneWidget);
      expect(find.text('Unlock older messages'), findsNothing);
    });
  });

  testWidgets('in a preview it is one line with the same words', (
    tester,
  ) async {
    await pump(
      tester,
      const UndecryptablePreviewText(),
      facts: _facts(backup: true, usableHere: false),
    );
    await tester.pump();

    final text = tester.widget<Text>(
      find.text('Sent before this device signed in.'),
    );
    expect(text.maxLines, 1);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });
}
