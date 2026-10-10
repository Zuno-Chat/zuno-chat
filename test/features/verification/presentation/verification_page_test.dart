import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/features/verification/presentation/qr_scanner_page.dart';
import 'package:zuno/features/verification/presentation/verification_page.dart';

import '../../../helpers/fake_permissions.dart';
import '../../../helpers/route_launcher.dart';
import 'verification_harness.dart';

const _waiting = 'Waiting for the other device…';
const _compare = 'Not together? Compare pictures instead';

void main() {
  Future<void> open(
    WidgetTester tester,
    FakeKeyVerification verification, {
    bool isOwnDevice = false,
    bool picturesFirst = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: routeLauncher(
            (_) => VerificationPage(
              keyVerification: verification,
              isOwnDevice: isOwnDevice,
              picturesFirst: picturesFirst,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pageBack();
    await settle(tester);
  }

  final qrImage = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is QrPainter,
  );

  group('waiting', () {
    for (final state in [
      KeyVerificationState.waitingAccept,
      KeyVerificationState.waitingSas,
      KeyVerificationState.askAccept,
    ]) {
      testWidgets('${state.name} shows a spinner', (tester) async {
        await open(tester, FakeKeyVerification(state: state));

        expect(find.text(_waiting), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });
    }

    testWidgets('a check of someone else asks to confirm it is them', (
      tester,
    ) async {
      await open(tester, FakeKeyVerification());
      expect(find.text('Confirm it is them'), findsOneWidget);
    });

    testWidgets('an own-device check asks to approve this device', (
      tester,
    ) async {
      await open(tester, FakeKeyVerification(), isOwnDevice: true);
      expect(find.text('Approve this device'), findsOneWidget);
    });
  });

  group('choosing a method', () {
    testWidgets('without a usable code it starts comparing pictures by '
        'itself, once', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askChoice,
      );
      await open(tester, verification);

      verification.moveTo(KeyVerificationState.askChoice);
      await tester.pump();

      expect(verification.calls, ['continue(${EventTypes.Sas})']);
      expect(find.text(_waiting), findsOneWidget);
    });

    testWidgets('a choice that arrives later starts comparing pictures too', (
      tester,
    ) async {
      final verification = FakeKeyVerification();
      await open(tester, verification);
      expect(verification.calls, isEmpty);

      verification.moveTo(KeyVerificationState.askChoice);
      await tester.pump();

      expect(verification.calls, ['continue(${EventTypes.Sas})']);
    });

    testWidgets('started from a call it compares pictures even when a code '
        'would work, and never shows the code', (tester) async {
      final verification = FakeKeyVerification(
        possibleMethods: showAndScan,
        qrBytes: matrixQrBytes,
      );
      await open(tester, verification, picturesFirst: true);

      verification.moveTo(KeyVerificationState.askChoice);
      await tester.pump();

      expect(verification.calls, ['continue(${EventTypes.Sas})']);
      expect(find.text(_waiting), findsOneWidget);
      expect(find.text('Let them scan this'), findsNothing);
    });

    testWidgets('with a code both ways it shows the code and offers to scan', (
      tester,
    ) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askChoice,
        possibleMethods: showAndScan,
        qrBytes: matrixQrBytes,
      );
      await open(tester, verification);

      expect(find.text('Let them scan this'), findsOneWidget);
      expect(qrImage, findsOneWidget);
      expect(find.text('Scan their code'), findsOneWidget);
      expect(find.text(_compare), findsOneWidget);
      expect(verification.calls, isEmpty);
    });

    testWidgets('an own-device check words the choice for two devices', (
      tester,
    ) async {
      await open(
        tester,
        FakeKeyVerification(
          state: KeyVerificationState.askChoice,
          possibleMethods: showAndScan,
          qrBytes: matrixQrBytes,
        ),
        isOwnDevice: true,
      );

      expect(find.text('Scan this with your other device'), findsOneWidget);
      expect(find.text('Scan the other device'), findsOneWidget);
    });

    testWidgets('no scan button when the other side cannot show a code', (
      tester,
    ) async {
      await open(
        tester,
        FakeKeyVerification(
          state: KeyVerificationState.askChoice,
          possibleMethods: showOnly,
          qrBytes: matrixQrBytes,
        ),
      );

      expect(qrImage, findsOneWidget);
      expect(find.text('Scan their code'), findsNothing);
      expect(find.text(_compare), findsOneWidget);
    });

    testWidgets('no code of its own when the other side cannot scan', (
      tester,
    ) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askChoice,
        possibleMethods: scanOnly,
        qrBytes: matrixQrBytes,
      );
      await open(tester, verification);

      expect(qrImage, findsNothing);
      expect(find.text('Let them scan this'), findsNothing);
      expect(find.text('Scan the code on their screen'), findsOneWidget);
      expect(find.text('Scan their code'), findsOneWidget);
      expect(verification.calls, isEmpty);
    });

    testWidgets('a code that could not be made never leaves a spinner behind', (
      tester,
    ) async {
      await open(
        tester,
        FakeKeyVerification(
          state: KeyVerificationState.askChoice,
          possibleMethods: showAndScan,
        ),
        isOwnDevice: true,
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(qrImage, findsNothing);
      expect(find.text('Scan the code on your other device'), findsOneWidget);
      expect(find.text('Scan the other device'), findsOneWidget);
    });

    testWidgets('no code and no way to scan falls back to pictures', (
      tester,
    ) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askChoice,
        possibleMethods: showOnly,
      );
      await open(tester, verification);

      expect(verification.calls, ['continue(${EventTypes.Sas})']);
      expect(find.text(_waiting), findsOneWidget);
    });

    testWidgets('Compare pictures instead starts the picture check', (
      tester,
    ) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askChoice,
        possibleMethods: showAndScan,
        qrBytes: matrixQrBytes,
      );
      await open(tester, verification);

      await tester.tap(find.text(_compare));
      await tester.pump();

      expect(verification.calls, ['continue(${EventTypes.Sas})']);
    });

    testWidgets('a picture check that cannot start ends the check instead of '
        'spinning forever', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askChoice,
      )..sendError = StateError('offline');
      await open(tester, verification);

      expect(tester.takeException(), isNull);
      expect(find.text('That did not finish'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(verification.calls.last, 'cancel(m.unknown, quiet)');
    });
  });

  group('scanning', () {
    late FakeScannerPlatform scanner;

    setUp(() {
      scanner = installFakeScanner();
      installFakePermissions();
    });

    Future<FakeKeyVerification> openScanner(
      WidgetTester tester, {
      bool isOwnDevice = false,
    }) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askChoice,
        possibleMethods: showAndScan,
        qrBytes: matrixQrBytes,
      );
      await open(tester, verification, isOwnDevice: isOwnDevice);
      await tester.tap(
        find.text(isOwnDevice ? 'Scan the other device' : 'Scan their code'),
      );
      await settle(tester);
      expect(find.byType(QrScannerPage), findsOneWidget);
      return verification;
    }

    testWidgets('a scanned code is handed over byte for byte', (tester) async {
      final verification = await openScanner(tester);
      expect(
        find.descendant(
          of: find.byType(QrScannerPage),
          matching: find.text('Scan their code'),
        ),
        findsOneWidget,
      );

      scanner.scan([decoded(matrixQrBytes)]);
      await settle(tester);

      expect(find.byType(QrScannerPage), findsNothing);
      expect(verification.calls, ['continue(${EventTypes.Reciprocate})']);
      expect(verification.scanned.single, matrixQrBytes);
    });

    testWidgets('the scanner is titled for an own-device check', (
      tester,
    ) async {
      await openScanner(tester, isOwnDevice: true);
      expect(find.text('Scan your other device'), findsOneWidget);
    });

    testWidgets('going back without scanning sends nothing', (tester) async {
      final verification = await openScanner(tester);

      await leave(tester);

      expect(find.byType(QrScannerPage), findsNothing);
      expect(find.text(_compare), findsOneWidget);
      expect(verification.calls, isEmpty);
    });

    testWidgets('a code scanned after the check stopped is not sent', (
      tester,
    ) async {
      final verification = await openScanner(tester);

      verification.stopWith('m.timeout');
      scanner.scan([decoded(matrixQrBytes)]);
      await settle(tester);

      expect(verification.calls, isEmpty);
      expect(find.text('Timed out'), findsOneWidget);
    });

    testWidgets('a code scanned after the other side chose pictures is not '
        'sent', (tester) async {
      final verification = await openScanner(tester);

      verification.moveTo(KeyVerificationState.askSas);
      scanner.scan([decoded(matrixQrBytes)]);
      await settle(tester);

      expect(verification.calls, isEmpty);
      expect(find.text('They match'), findsOneWidget);
    });

    testWidgets('a scan that cannot be sent says so', (tester) async {
      final verification = await openScanner(tester);
      verification.sendError = StateError('offline');

      scanner.scan([decoded(matrixQrBytes)]);
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Could not send that. Try again.'), findsOneWidget);
      expect(find.text(_compare), findsOneWidget);
    });
  });

  group('comparing pictures', () {
    testWidgets('shows all seven with their names', (tester) async {
      final emojis = testEmojis();
      await open(
        tester,
        FakeKeyVerification(
          state: KeyVerificationState.askSas,
          sasEmojis: emojis,
        ),
      );

      expect(
        find.text('Check these match. Read them out to each other.'),
        findsOneWidget,
      );
      for (final emoji in emojis) {
        expect(find.text(emoji.emoji), findsOneWidget);
        expect(find.text(emoji.name), findsOneWidget);
      }
    });

    testWidgets('an own-device check words it for two devices', (tester) async {
      await open(
        tester,
        FakeKeyVerification(
          state: KeyVerificationState.askSas,
          sasEmojis: testEmojis(),
        ),
        isOwnDevice: true,
      );

      expect(find.text('Check these match on both devices'), findsOneWidget);
    });

    testWidgets('They match accepts and They do not match rejects, and a '
        'second tap while the first is on its way is dropped', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askSas,
        sasEmojis: testEmojis(),
      )..sendGate = Completer<void>();
      await open(tester, verification);

      await tester.tap(find.text('They match'));
      await tester.pump();
      await tester.tap(find.text('They match'));
      await tester.pump();
      await tester.tap(find.text('They do not match'));
      await tester.pump();

      expect(verification.calls, ['acceptSas']);

      verification.sendGate!.complete();
      await tester.pump();
      await tester.tap(find.text('They do not match'));
      await tester.pump();

      expect(verification.calls, ['acceptSas', 'rejectSas']);
    });

    testWidgets('an answer that cannot be sent says so and can be retried', (
      tester,
    ) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askSas,
        sasEmojis: testEmojis(),
      )..sendError = StateError('offline');
      await open(tester, verification);

      await tester.tap(find.text('They match'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Could not send that. Try again.'), findsOneWidget);

      verification.sendError = null;
      await tester.tap(find.text('They match'));
      await tester.pump();

      expect(verification.calls, ['acceptSas', 'acceptSas']);
    });
  });

  group('after a scan', () {
    testWidgets('the scanning side is told to finish on the other one', (
      tester,
    ) async {
      await open(
        tester,
        FakeKeyVerification(state: KeyVerificationState.showQRSuccess),
      );

      expect(find.text('Scanned'), findsOneWidget);
      expect(
        find.text('Tell them it worked so they can finish on their side.'),
        findsOneWidget,
      );
    });

    testWidgets('the scanning side of an own-device check', (tester) async {
      await open(
        tester,
        FakeKeyVerification(state: KeyVerificationState.showQRSuccess),
        isOwnDevice: true,
      );

      expect(
        find.text('Confirm on your other device to finish.'),
        findsOneWidget,
      );
    });

    testWidgets('the scanned side names who scanned', (tester) async {
      await open(
        tester,
        FakeKeyVerification(state: KeyVerificationState.confirmQRScan),
      );

      expect(find.text('Did their screen show a check mark?'), findsOneWidget);
      expect(find.textContaining('@bob scanned your code.'), findsOneWidget);
    });

    testWidgets('the scanned side of an own-device check talks about the '
        'device, not a person', (tester) async {
      await open(
        tester,
        FakeKeyVerification(state: KeyVerificationState.confirmQRScan),
        isOwnDevice: true,
      );

      expect(
        find.text('Did your other device show a check mark?'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your other device scanned this code.'),
        findsOneWidget,
      );
      expect(find.textContaining('their'), findsNothing);
    });

    testWidgets('Yes, finish confirms the scan', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.confirmQRScan,
      );
      await open(tester, verification);

      await tester.tap(find.text('Yes, finish'));
      await tester.pump();

      expect(verification.calls, ['acceptQRScanConfirmation']);
    });

    testWidgets('No, stop cancels as the user', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.confirmQRScan,
      );
      await open(tester, verification);

      await tester.tap(find.text('No, stop'));
      await settle(tester);

      expect(verification.calls, ['cancel(m.user)']);
      expect(find.text('Canceled'), findsOneWidget);
    });
  });

  group('done', () {
    testWidgets('a confirmed person, and Back to chat closes', (tester) async {
      await open(tester, FakeKeyVerification(state: KeyVerificationState.done));

      expect(find.text('Confirmed'), findsOneWidget);
      expect(
        find.textContaining('You are talking to the real @bob.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Back to chat'));
      await settle(tester);

      expect(find.byType(VerificationPage), findsNothing);
    });

    testWidgets('an approved device, and Done closes', (tester) async {
      await open(
        tester,
        FakeKeyVerification(state: KeyVerificationState.done),
        isOwnDevice: true,
      );

      expect(find.text('Approved'), findsOneWidget);
      expect(
        find.text('This device can now read your messages.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Done'));
      await settle(tester);

      expect(find.byType(VerificationPage), findsNothing);
    });
  });

  group('stopped', () {
    testWidgets('a cancel from either side reads as canceled', (tester) async {
      final verification = FakeKeyVerification();
      await open(tester, verification);

      verification.stopWith('m.user', reason: 'm.user');
      await tester.pump();

      expect(find.text('Canceled'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      expect(find.textContaining('m.user'), findsNothing);
    });

    testWidgets('a mismatch carries the attention mark', (tester) async {
      final verification = FakeKeyVerification();
      await open(tester, verification, isOwnDevice: true);

      verification.stopWith('m.mismatched_sas');
      await tester.pump();

      expect(find.text('The codes did not match'), findsOneWidget);
      expect(find.byIcon(attentionIcon), findsOneWidget);
      expect(find.textContaining('this device was not'), findsOneWidget);
    });

    testWidgets('an error without a cancel still explains itself', (
      tester,
    ) async {
      await open(
        tester,
        FakeKeyVerification(state: KeyVerificationState.error),
      );

      expect(find.text('That did not finish'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('a locked device is sent to its recovery code', (tester) async {
      await open(
        tester,
        FakeKeyVerification(state: KeyVerificationState.askSSSS),
      );

      expect(find.text('Unlock this device first'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });
  });

  group('leaving', () {
    testWidgets('partway through cancels as the user', (tester) async {
      final verification = FakeKeyVerification();
      await open(tester, verification);

      await leave(tester);

      expect(verification.calls, ['cancel(m.user)']);
      expect(verification.onUpdate, isNull);
    });

    testWidgets('after it finished cancels nothing', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.done,
      );
      await open(tester, verification);

      await leave(tester);

      expect(verification.calls, isEmpty);
      expect(verification.onUpdate, isNull);
    });

    testWidgets('after it stopped cancels nothing', (tester) async {
      final verification = FakeKeyVerification();
      await open(tester, verification);
      verification.stopWith('m.timeout');
      await tester.pump();

      await leave(tester);

      expect(verification.calls, isEmpty);
    });

    testWidgets('a cancel that cannot be sent stays quiet', (tester) async {
      final verification = FakeKeyVerification()
        ..sendError = StateError('offline');
      await open(tester, verification);

      await leave(tester);

      expect(tester.takeException(), isNull);
      expect(verification.calls, ['cancel(m.user)']);
    });
  });
}
