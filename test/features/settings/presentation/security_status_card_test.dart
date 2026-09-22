import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/features/settings/presentation/security_status_card.dart';

void main() {
  Future<void> pump(WidgetTester tester, AccountSecurityStatus status) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSecurityStatusProvider.overrideWithValue(
            AsyncValue.data(status),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SecurityStatusCard(onAction: (_) {})),
        ),
      ),
    );
  }

  testWidgets('a settled account gets the muted check and no stripe', (
    tester,
  ) async {
    await pump(tester, AccountSecurityStatus.protected);

    expect(find.byIcon(settledIcon), findsOneWidget);
    expect(find.byType(AttentionStripe), findsNothing);
  });

  testWidgets('a state that needs action gets the full attention treatment', (
    tester,
  ) async {
    await pump(tester, AccountSecurityStatus.noRecovery);

    expect(find.byIcon(attentionIcon), findsOneWidget);
    expect(find.byType(AttentionStripe), findsOneWidget);
  });

  testWidgets('a failure to read the status is not dressed up as an alert', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSecurityStatusProvider.overrideWithValue(
            AsyncValue.error('offline', StackTrace.empty),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SecurityStatusCard(onAction: (_) {})),
        ),
      ),
    );

    expect(find.byType(AttentionStripe), findsNothing);
    expect(find.byIcon(attentionIcon), findsNothing);
  });
}
