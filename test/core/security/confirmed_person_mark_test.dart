import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/confirmed_person_mark.dart';
import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

import '../../helpers/zuno_app.dart';

void main() {
  Future<void> pump(WidgetTester tester, UserTrustState trust) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [userTrustProvider.overrideWith((ref, _) => trust)],
          child: inZunoApp(
            const ConfirmedPersonMark(
              userId: '@bob:example.org',
              orElse: Text('person mark'),
            ),
          ),
        ),
      );

  testWidgets("a confirmed person gets the confirmed mark in the theme's "
      'orange', (tester) async {
    await pump(tester, UserTrustState.confirmed);

    expect(find.bySemanticsLabel('Confirmed'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(confirmedPersonIcon));
    expect(icon.color, zunoLightTheme.colorScheme.primary);
    expect(find.text('person mark'), findsNothing);
  });

  testWidgets('someone not confirmed keeps what shows otherwise', (
    tester,
  ) async {
    await pump(tester, UserTrustState.unconfirmed);

    expect(find.byIcon(confirmedPersonIcon), findsNothing);
    expect(find.text('person mark'), findsOneWidget);
  });
}
