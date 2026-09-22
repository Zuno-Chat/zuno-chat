import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/features/verification/presentation/confirm_person.dart';
import 'package:zuno/features/verification/presentation/verification_page.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [matrixClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => confirmPerson(
                context,
                ref,
                '@bob:example.org',
                setUpRecovery: (_) async {},
              ),
              child: const Text('confirm'),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('going back from recovery setup aborts quietly', (tester) async {
    await pump(tester);
    await tester.tap(find.text('confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Set up recovery first'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(VerificationPage), findsNothing);
    expect(find.textContaining("haven't set up recovery"), findsNothing);
    expect(find.textContaining("Couldn't start"), findsNothing);
  });

  testWidgets('Not now aborts quietly', (tester) async {
    await pump(tester);
    await tester.tap(find.text('confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.byType(VerificationPage), findsNothing);
    expect(find.textContaining("haven't set up recovery"), findsNothing);
  });
}
