import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/ui/step_hero.dart';
import 'package:zuno/features/settings/presentation/secure_backup_page.dart';
import 'package:zuno/features/verification/presentation/approve_this_device_page.dart';
import 'package:zuno/features/verification/presentation/verification_page.dart';

import '../../../helpers/fake_encryption.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/route_launcher.dart';
import 'verification_harness.dart';

const _me = '@me:example.org';
const _approve = 'Approve from another device';
const _enterCode = 'Enter recovery code';
const _startOver = 'Lost the code? Start over';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool showStartOver,
    Size size = const Size(360, 640),
    FakeViewPadding padding = const FakeViewPadding(top: 24, bottom: 48),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = padding;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(buildTestClient(userId: _me)),
        ],
        child: MaterialApp(
          home: ApproveThisDevicePage(showStartOver: showStartOver),
        ),
      ),
    );
    await tester.pump();
  }

  double top(WidgetTester tester, String label) =>
      tester.getRect(find.text(label)).top;

  testWidgets('fits a small phone with the ways forward in order, Not now '
      'last', (tester) async {
    await pump(tester, showStartOver: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(StepHero), findsOneWidget);
    final order = [
      _approve,
      _enterCode,
      _startOver,
      'Not now',
    ].map((label) => top(tester, label)).toList();
    expect(order, [...order]..sort());
    expect(
      tester.getRect(find.widgetWithText(TextButton, 'Not now')).bottom,
      lessThanOrEqualTo(640 - 48),
    );
  });

  testWidgets('the buttons sit right under the explanation, not at the '
      'bottom of a tall screen', (tester) async {
    await pump(tester, showStartOver: true, size: const Size(412, 915));

    expect(tester.takeException(), isNull);
    final explanationBottom = tester
        .getRect(
          find.text('Approve this device and your message history comes back.'),
        )
        .bottom;
    expect(top(tester, _approve) - explanationBottom, lessThan(60));
  });

  testWidgets('Start over is offered only where it was asked for', (
    tester,
  ) async {
    await pump(tester, showStartOver: false);

    expect(find.text(_startOver), findsNothing);
    expect(find.text(_enterCode), findsOneWidget);
  });

  testWidgets('in landscape the explanation is still readable', (tester) async {
    await pump(
      tester,
      showStartOver: true,
      size: const Size(640, 360),
      padding: const FakeViewPadding(top: 24),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(Scrollable).first).height,
      greaterThan(200),
    );
  });

  group('ways forward', () {
    late Client client;
    late List<bool> recoveryOpened;
    late void Function() duringRecovery;

    setUp(() {
      client = buildTestClient(userId: _me);
      recoveryOpened = [];
      duringRecovery = () {};
    });

    Future<void> openRecovery(
      BuildContext context, {
      required bool restoreExisting,
    }) async {
      recoveryOpened.add(restoreExisting);
      duringRecovery();
    }

    Future<void> open(
      WidgetTester tester, {
      VoidCallback? onFinished,
      RecoveryOpener? recovery,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [matrixClientProvider.overrideWithValue(client)],
          child: MaterialApp(
            home: Scaffold(
              body: routeLauncher(
                (_) => ApproveThisDevicePage(
                  showStartOver: true,
                  onFinished: onFinished,
                  openRecovery: recovery ?? openRecovery,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    Future<void> tap(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await settle(tester);
    }

    bool enabled(WidgetTester tester, String label) => tester
        .widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        )
        .enabled;

    final page = find.byType(ApproveThisDevicePage);

    testWidgets('Not now hands over to the caller when it asked to decide', (
      tester,
    ) async {
      var finished = 0;
      await open(tester, onFinished: () => finished++);

      await tap(tester, 'Not now');

      expect(finished, 1);
      expect(page, findsOneWidget);
    });

    group('Approve from another device', () {
      testWidgets('without a device list it says so and starts nothing', (
        tester,
      ) async {
        await open(tester);

        await tap(tester, _approve);

        expect(
          find.text('Could not find your other devices yet.'),
          findsOneWidget,
        );
        expect(find.byType(VerificationPage), findsNothing);
        expect(enabled(tester, _approve), isTrue);
      });

      testWidgets('a start that fails says so and can be retried', (
        tester,
      ) async {
        final keys = fakeDeviceKeysOf(client, _me)
          ..onStart = () async => throw StateError('offline');
        await open(tester);

        await tap(tester, _approve);

        expect(tester.takeException(), isNull);
        expect(find.text('Could not start. Try again.'), findsOneWidget);
        expect(find.byType(VerificationPage), findsNothing);
        expect(page, findsOneWidget);
        expect(enabled(tester, _approve), isTrue);

        await tap(tester, _approve);
        expect(keys.starts, 2);
      });

      testWidgets('the real device list without encryption fails the same '
          'way', (tester) async {
        client.userDeviceKeys[_me] = DeviceKeysList(_me, client);
        await open(tester);

        await tap(tester, _approve);

        expect(find.text('Could not start. Try again.'), findsOneWidget);
      });

      testWidgets('while it starts only Not now stays available', (
        tester,
      ) async {
        final gate = Completer<KeyVerification>();
        fakeDeviceKeysOf(client, _me).onStart = () => gate.future;
        await open(tester);

        await tester.tap(find.text(_approve));
        await tester.pump();

        expect(enabled(tester, _approve), isFalse);
        expect(enabled(tester, _enterCode), isFalse);
        expect(enabled(tester, _startOver), isFalse);
        expect(enabled(tester, 'Not now'), isTrue);

        gate.complete(FakeKeyVerification(userId: _me));
        await settle(tester);

        expect(find.byType(VerificationPage), findsOneWidget);
      });

      testWidgets('opens the check as an own-device check', (tester) async {
        fakeDeviceKeysOf(client, _me).onStart = () async =>
            FakeKeyVerification(userId: _me);
        await open(tester);

        await tap(tester, _approve);

        expect(
          tester
              .widget<VerificationPage>(find.byType(VerificationPage))
              .isOwnDevice,
          isTrue,
        );
      });

      testWidgets('an approved device closes both screens', (tester) async {
        final verification = FakeKeyVerification(userId: _me);
        fakeDeviceKeysOf(client, _me).onStart = () async => verification;
        await open(tester);
        await tap(tester, _approve);

        verification.moveTo(KeyVerificationState.done);
        await tester.pump();
        await tap(tester, 'Done');

        expect(find.byType(VerificationPage), findsNothing);
        expect(page, findsNothing);
        expect(find.text('open'), findsOneWidget);
      });

      testWidgets('an approved device hands over to the caller once', (
        tester,
      ) async {
        var finished = 0;
        final verification = FakeKeyVerification(
          userId: _me,
          state: KeyVerificationState.done,
        );
        fakeDeviceKeysOf(client, _me).onStart = () async => verification;
        await open(tester, onFinished: () => finished++);
        await tap(tester, _approve);

        await tap(tester, 'Done');

        expect(finished, 1);
      });

      testWidgets('a check that stopped leaves the other ways open', (
        tester,
      ) async {
        final verification = FakeKeyVerification(userId: _me);
        fakeDeviceKeysOf(client, _me).onStart = () async => verification;
        await open(tester);
        await tap(tester, _approve);

        verification.stopWith('m.timeout');
        await tester.pump();
        await tester.pageBack();
        await settle(tester);

        expect(find.byType(VerificationPage), findsNothing);
        expect(page, findsOneWidget);
        expect(enabled(tester, _enterCode), isTrue);
      });

      testWidgets('a check that started after the page closed is canceled', (
        tester,
      ) async {
        final gate = Completer<KeyVerification>();
        final verification = FakeKeyVerification(userId: _me);
        fakeDeviceKeysOf(client, _me).onStart = () => gate.future;
        await open(tester);
        await tester.tap(find.text(_approve));
        await tester.pump();
        await tap(tester, 'Not now');
        expect(page, findsNothing);

        gate.complete(verification);
        await settle(tester);

        expect(find.byType(VerificationPage), findsNothing);
        expect(verification.calls, ['cancel(m.user)']);
      });
    });

    group('Enter recovery code', () {
      testWidgets('opens recovery to restore the existing code', (
        tester,
      ) async {
        await open(tester);

        await tap(tester, _enterCode);

        expect(recoveryOpened, [true]);
      });

      testWidgets('a device that is still locked afterwards keeps the page', (
        tester,
      ) async {
        client = EncryptedTestClient(userId: _me)..setUpRecovery();
        await open(tester);

        await tap(tester, _enterCode);

        expect(page, findsOneWidget);
        expect(enabled(tester, _approve), isTrue);
      });

      testWidgets('an unlocked device closes the page', (tester) async {
        final encrypted = EncryptedTestClient(userId: _me)..setUpRecovery();
        client = encrypted;
        duringRecovery = encrypted.unlockRecovery;
        await open(tester);

        await tap(tester, _enterCode);

        expect(page, findsNothing);
        expect(find.text('open'), findsOneWidget);
      });

      testWidgets('opens the recovery screen when nothing else is given', (
        tester,
      ) async {
        client = EncryptedTestClient(userId: _me)..setUpRecovery();
        await open(tester, recovery: openSecureBackup);

        await tap(tester, _enterCode);

        expect(
          tester
              .widget<SecureBackupPage>(find.byType(SecureBackupPage))
              .autoRestoreExisting,
          isTrue,
        );
      });
    });

    group('Start over', () {
      testWidgets('warns first, and Cancel changes nothing', (tester) async {
        await open(tester);

        await tap(tester, _startOver);

        expect(find.text('Start over with a new code?'), findsOneWidget);
        expect(find.textContaining('Nobody can undo this.'), findsOneWidget);

        await tap(tester, 'Cancel');

        expect(recoveryOpened, isEmpty);
        expect(page, findsOneWidget);
      });

      testWidgets('dismissing the warning changes nothing', (tester) async {
        await open(tester);
        await tap(tester, _startOver);

        await tester.tapAt(const Offset(5, 5));
        await settle(tester);

        expect(find.text('Start over with a new code?'), findsNothing);
        expect(recoveryOpened, isEmpty);
      });

      testWidgets('Start over opens recovery for a new code', (tester) async {
        await open(tester);
        await tap(tester, _startOver);

        await tap(tester, 'Start over');

        expect(recoveryOpened, [false]);
      });
    });
  });
}
