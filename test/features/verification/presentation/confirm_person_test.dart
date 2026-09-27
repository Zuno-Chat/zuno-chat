import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/confirmed_identity_store.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/secure_backup_page.dart';
import 'package:zuno/features/verification/presentation/confirm_person.dart';
import 'package:zuno/features/verification/presentation/verification_page.dart';

import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_encryption.dart';
import '../../../helpers/fake_matrix.dart';
import 'verification_harness.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';
const _nothingToConfirm =
    'They have not set up recovery yet, so there is nothing to confirm.';
const _couldNotStart = 'Could not start. Try again.';

void main() {
  late Client client;
  late SharedPreferences preferences;
  late ValueNotifier<bool> callerShown;
  late int recoverySetUps;
  late void Function() duringRecoverySetUp;
  Completer<void>? recoverySetUpGate;

  setUp(() async {
    client = buildTestClient(userId: _me);
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    callerShown = ValueNotifier(true);
    recoverySetUps = 0;
    duringRecoverySetUp = () {};
    recoverySetUpGate = null;
  });

  tearDown(() => callerShown.dispose());

  EncryptedTestClient readyClient() => client = EncryptedTestClient(userId: _me)
    ..setUpRecovery()
    ..unlockRecovery();

  Future<void> pump(WidgetTester tester, {bool withSeam = true}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            matrixClientProvider.overrideWithValue(client),
            sharedPreferencesProvider.overrideWithValue(preferences),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: callerShown,
                builder: (context, shown, _) => shown
                    ? Consumer(
                        builder: (context, ref, _) => TextButton(
                          onPressed: () => confirmPerson(
                            context,
                            ref,
                            _bob,
                            setUpRecovery: withSeam
                                ? (_) async {
                                    recoverySetUps++;
                                    duringRecoverySetUp();
                                    await recoverySetUpGate?.future;
                                  }
                                : null,
                          ),
                          child: const Text('confirm'),
                        ),
                      )
                    : const SizedBox(),
              ),
            ),
          ),
        ),
      );

  Future<void> start(WidgetTester tester, {bool withSeam = true}) async {
    await pump(tester, withSeam: withSeam);
    await tester.tap(find.text('confirm'));
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settle(tester);
  }

  void expectQuiet() {
    expect(find.byType(VerificationPage), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  }

  group('canConfirmPerson', () {
    test('never yourself', () {
      testMasterKey(client, _me);
      expect(canConfirmPerson(client, _me), isFalse);
    });

    test('not someone whose devices are unknown', () {
      expect(canConfirmPerson(client, _bob), isFalse);
    });

    test('not someone without an identity', () {
      setTestDevices(client, _bob, {'PHONE': null});
      expect(canConfirmPerson(client, _bob), isFalse);
    });

    test('someone with an identity', () {
      testMasterKey(client, _bob);
      expect(canConfirmPerson(client, _bob), isTrue);
    });
  });

  group('before recovery is set up', () {
    testWidgets('going back from recovery setup aborts quietly', (
      tester,
    ) async {
      await start(tester);

      expect(find.text('Set up recovery first'), findsOneWidget);

      await tap(tester, 'Continue');

      expect(recoverySetUps, 1);
      expectQuiet();
    });

    testWidgets('Not now aborts quietly', (tester) async {
      await start(tester);

      await tap(tester, 'Not now');

      expect(recoverySetUps, 0);
      expectQuiet();
    });

    testWidgets('dismissing the question aborts quietly', (tester) async {
      await start(tester);

      await tester.tapAt(const Offset(5, 5));
      await settle(tester);

      expect(find.text('Set up recovery first'), findsNothing);
      expect(recoverySetUps, 0);
      expectQuiet();
    });

    testWidgets('a locked device is asked too, recovery or not', (
      tester,
    ) async {
      client = EncryptedTestClient(userId: _me)..setUpRecovery();
      await start(tester);

      expect(find.text('Set up recovery first'), findsOneWidget);
    });

    testWidgets('recovery that got set up carries on to the check', (
      tester,
    ) async {
      final encrypted = client = EncryptedTestClient(userId: _me);
      duringRecoverySetUp = () => encrypted
        ..setUpRecovery()
        ..unlockRecovery();
      fakeDeviceKeysOf(client, _bob).onStart = () async =>
          FakeKeyVerification();
      testMasterKey(client, _bob);
      await start(tester);

      await tap(tester, 'Continue');

      expect(find.byType(VerificationPage), findsOneWidget);
    });

    testWidgets('the caller going away during setup stops it there', (
      tester,
    ) async {
      final encrypted = client = EncryptedTestClient(userId: _me);
      duringRecoverySetUp = () => encrypted
        ..setUpRecovery()
        ..unlockRecovery();
      final gate = recoverySetUpGate = Completer<void>();
      final keys = fakeDeviceKeysOf(client, _bob)
        ..onStart = () async => FakeKeyVerification();
      testMasterKey(client, _bob);
      await start(tester);
      await tap(tester, 'Continue');

      callerShown.value = false;
      await tester.pump();
      gate.complete();
      await settle(tester);

      expect(recoverySetUps, 1);
      expect(keys.starts, 0);
      expectQuiet();
    });

    testWidgets('without recovery it opens a fresh setup', (tester) async {
      client = EncryptedTestClient(userId: _me);
      await start(tester, withSeam: false);

      await tap(tester, 'Continue');

      expect(
        tester
            .widget<SecureBackupPage>(find.byType(SecureBackupPage))
            .autoRestoreExisting,
        isNull,
      );
    });

    testWidgets('with recovery on a locked device it opens a restore', (
      tester,
    ) async {
      client = EncryptedTestClient(userId: _me)..setUpRecovery();
      await start(tester, withSeam: false);

      await tap(tester, 'Continue');

      expect(
        tester
            .widget<SecureBackupPage>(find.byType(SecureBackupPage))
            .autoRestoreExisting,
        isTrue,
      );
    });
  });

  group('with recovery in place', () {
    setUp(readyClient);

    testWidgets('someone whose devices are unknown has nothing to confirm', (
      tester,
    ) async {
      await start(tester);

      expect(find.text('Set up recovery first'), findsNothing);
      expect(find.text(_nothingToConfirm), findsOneWidget);
      expect(find.byType(VerificationPage), findsNothing);
    });

    testWidgets('someone without an identity has nothing to confirm', (
      tester,
    ) async {
      final keys = fakeDeviceKeysOf(client, _bob)
        ..onStart = () async => FakeKeyVerification();
      await start(tester);

      expect(find.text(_nothingToConfirm), findsOneWidget);
      expect(keys.starts, 0);
    });

    testWidgets('a start that fails says so', (tester) async {
      fakeDeviceKeysOf(client, _bob).onStart = () async =>
          throw StateError('offline');
      testMasterKey(client, _bob);
      await start(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(_couldNotStart), findsOneWidget);
      expect(find.byType(VerificationPage), findsNothing);
    });

    testWidgets('opens the check for that person', (tester) async {
      final verification = FakeKeyVerification();
      fakeDeviceKeysOf(client, _bob).onStart = () async => verification;
      testMasterKey(client, _bob);
      await start(tester);

      final page = tester.widget<VerificationPage>(
        find.byType(VerificationPage),
      );
      expect(page.keyVerification, same(verification));
      expect(page.isOwnDevice, isFalse);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a confirmed person is remembered with their identity', (
      tester,
    ) async {
      final verification = FakeKeyVerification();
      fakeDeviceKeysOf(client, _bob).onStart = () async => verification;
      final identity = testMasterKey(client, _bob);
      await start(tester);

      await identity.setVerified(true, false);
      verification.moveTo(KeyVerificationState.done);
      await tester.pump();
      await tap(tester, 'Back to chat');

      expect(
        ConfirmedIdentityStore(preferences).confirmedIdentityKey(_bob),
        identity.ed25519Key,
      );
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('backing out remembers nobody', (tester) async {
      final verification = FakeKeyVerification();
      fakeDeviceKeysOf(client, _bob).onStart = () async => verification;
      testMasterKey(client, _bob);
      await start(tester);

      await tester.pageBack();
      await settle(tester);

      expect(verification.calls, ['cancel(m.user)']);
      expect(
        ConfirmedIdentityStore(preferences).confirmedIdentityKey(_bob),
        isNull,
      );
    });

    testWidgets('a check that started after the caller went away is '
        'canceled', (tester) async {
      final gate = Completer<KeyVerification>();
      final verification = FakeKeyVerification();
      fakeDeviceKeysOf(client, _bob).onStart = () => gate.future;
      testMasterKey(client, _bob);
      await start(tester);

      callerShown.value = false;
      await tester.pump();
      gate.complete(verification);
      await settle(tester);

      expect(find.byType(VerificationPage), findsNothing);
      expect(verification.calls, ['cancel(m.user)']);
    });
  });
}
