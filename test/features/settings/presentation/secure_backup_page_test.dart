import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/recovery_code.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/ui/step_layout.dart';
import 'package:zuno/features/settings/presentation/secure_backup_page.dart';

import '../../../helpers/fake_matrix.dart';

class _FakeBootstrap extends Fake implements Bootstrap {
  _FakeBootstrap(this._state);

  BootstrapState _state;
  final calls = <String>[];
  Completer<void>? newSsssGate;

  @override
  void Function(Bootstrap)? onUpdate;

  @override
  OpenSSSS? newSsssKey;

  @override
  Map<String, OpenSSSS>? oldSsssKeys;

  @override
  BootstrapState get state => _state;

  @override
  set state(BootstrapState newState) {
    _state = newState;
    onUpdate?.call(this);
  }

  @override
  void wipeSsss(bool wipe) => calls.add('wipeSsss($wipe)');

  @override
  void useExistingSsss(bool use, {String? keyIdentifier}) =>
      calls.add('useExistingSsss($use)');

  @override
  void ignoreBadSecrets(bool ignore) => calls.add('ignoreBadSecrets($ignore)');

  @override
  void unlockedSsss() => calls.add('unlockedSsss');

  @override
  Future<void> newSsss([String? passphrase, String? name]) async {
    calls.add('newSsss($passphrase)');
    await newSsssGate?.future;
  }

  @override
  Future<void> openExistingSsss() async => calls.add('openExistingSsss');

  @override
  Future<void> wipeCrossSigning(bool wipe) async =>
      calls.add('wipeCrossSigning($wipe)');

  @override
  Future<void> askSetupCrossSigning({
    bool selfSign = true,
    bool setupMasterKey = false,
    bool setupSelfSigningKey = false,
    bool setupUserSigningKey = false,
  }) async => calls.add(
    'askSetupCrossSigning($setupMasterKey,$setupSelfSigningKey,'
    '$setupUserSigningKey)',
  );

  @override
  void wipeOnlineKeyBackup(bool wipe) =>
      calls.add('wipeOnlineKeyBackup($wipe)');

  @override
  Future<void> askSetupOnlineKeyBackup(bool setup) async =>
      calls.add('askSetupOnlineKeyBackup($setup)');
}

class _FakeKey extends Fake implements OpenSSSS {
  _FakeKey({this.accepts, this.recoveryKey});

  final String? accepts;
  final attempts = <String?>[];
  bool _unlocked = false;

  @override
  final String? recoveryKey;

  @override
  bool get isUnlocked => _unlocked;

  @override
  Future<void> unlock({
    String? passphrase,
    String? recoveryKey,
    String? keyOrPassphrase,
    bool postUnlock = true,
  }) async {
    attempts.add(keyOrPassphrase);
    if (keyOrPassphrase != accepts) throw Exception('wrong key');
    _unlocked = true;
  }
}

void main() {
  final wordlist = RecoveryWordlist.parse(
    File('assets/wordlist/recovery_words.txt').readAsStringSync(),
  );

  late List<_FakeBootstrap> created;

  Future<_FakeBootstrap> pump(
    WidgetTester tester,
    BootstrapState state, {
    SecureBackupMode mode = SecureBackupMode.recoveryCode,
    bool? autoRestoreExisting,
    void Function(_FakeBootstrap bootstrap)? prepare,
    double keyboard = 0,
  }) async {
    created = [];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(
            buildTestClient(userId: '@me:example.org'),
          ),
          recoveryWordlistProvider.overrideWith((ref) async => wordlist),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SecureBackupPage(
                    mode: mode,
                    autoRestoreExisting: autoRestoreExisting,
                    createBootstrap: (client, onUpdate) {
                      final bootstrap = _FakeBootstrap(
                        created.isEmpty ? state : BootstrapState.loading,
                      )..onUpdate = onUpdate;
                      if (created.isEmpty) prepare?.call(bootstrap);
                      created.add(bootstrap);
                      return bootstrap;
                    },
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return created.single;
  }

  Finder filled(String label) => find.widgetWithText(FilledButton, label);

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<ButtonStyleButton>(button).onPressed != null;

  testWidgets('says it is setting up while there is nothing to ask', (
    tester,
  ) async {
    await pump(tester, BootstrapState.loading);

    expect(find.text('Setting up…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('answers the setup questions nobody needs to see', (
    tester,
  ) async {
    final bootstrap = await pump(tester, BootstrapState.loading);

    for (final state in [
      BootstrapState.askUseExistingSsss,
      BootstrapState.askWipeCrossSigning,
      BootstrapState.askSetupCrossSigning,
      BootstrapState.askWipeOnlineKeyBackup,
      BootstrapState.askSetupOnlineKeyBackup,
    ]) {
      bootstrap.state = state;
      await tester.pump();
      expect(find.text('Setting up…'), findsOneWidget, reason: '$state');
    }
    expect(bootstrap.calls, [
      'useExistingSsss(true)',
      'wipeCrossSigning(true)',
      'askSetupCrossSigning(true,true,true)',
      'wipeOnlineKeyBackup(true)',
      'askSetupOnlineKeyBackup(true)',
    ]);
  });

  group('an account that already has recovery', () {
    testWidgets('offers to enter the code, which keeps what is there', (
      tester,
    ) async {
      final bootstrap = await pump(tester, BootstrapState.askWipeSsss);

      expect(
        find.text('This account already has recovery set up'),
        findsOneWidget,
      );
      await tester.tap(filled('Enter recovery code'));
      await tester.pump();

      expect(bootstrap.calls, ['wipeSsss(false)']);
    });

    testWidgets('starting over asks for the password first', (tester) async {
      final bootstrap = await pump(tester, BootstrapState.askWipeSsss);

      await tester.tap(find.text('Start over with a new code'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm your password'), findsOneWidget);
      expect(bootstrap.calls, isEmpty);

      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.tap(filled('Confirm'));
      await tester.pumpAndSettle();

      expect(bootstrap.calls, ['wipeSsss(true)']);
    });

    testWidgets('backing out of the password starts nothing over', (
      tester,
    ) async {
      final bootstrap = await pump(tester, BootstrapState.askWipeSsss);

      await tester.tap(find.text('Start over with a new code'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(bootstrap.calls, isEmpty);
      expect(find.byType(SecureBackupPage), findsOneWidget);
    });

    testWidgets('a caller that wants the existing recovery skips the choice', (
      tester,
    ) async {
      final bootstrap = await pump(
        tester,
        BootstrapState.askWipeSsss,
        autoRestoreExisting: true,
      );

      expect(bootstrap.calls, ['wipeSsss(false)']);
    });
  });

  group('unreadable recovery data', () {
    testWidgets('Continue anyway sets up fresh recovery', (tester) async {
      final bootstrap = await pump(tester, BootstrapState.askBadSsss);

      await tester.tap(filled('Continue anyway'));
      await tester.pump();

      expect(bootstrap.calls, ['ignoreBadSecrets(true)']);
    });

    testWidgets('Cancel leaves the page and changes nothing', (tester) async {
      final bootstrap = await pump(tester, BootstrapState.askBadSsss);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(SecureBackupPage), findsNothing);
      expect(bootstrap.calls, isEmpty);
    });
  });

  group('creating new recovery', () {
    testWidgets('the default is the twelve-word code', (tester) async {
      await pump(tester, BootstrapState.askNewSsss);

      expect(
        find.text('These 12 words are your recovery code'),
        findsOneWidget,
      );
    });

    testWidgets('a security key is generated once, and the button waits', (
      tester,
    ) async {
      final gate = Completer<void>();
      final bootstrap = await pump(
        tester,
        BootstrapState.askNewSsss,
        mode: SecureBackupMode.key,
        prepare: (b) => b.newSsssGate = gate,
      );

      await tester.tap(filled('Generate security key'));
      await tester.pump();

      expect(bootstrap.calls, ['newSsss(null)']);
      final button = find.byType(FilledButton);
      expect(enabled(tester, button), isFalse);
      expect(
        find.descendant(
          of: button,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(enabled(tester, filled('Generate security key')), isTrue);
    });

    testWidgets('a weak security phrase is refused before anything is set', (
      tester,
    ) async {
      final bootstrap = await pump(
        tester,
        BootstrapState.askNewSsss,
        mode: SecureBackupMode.phrase,
      );

      await tester.enterText(find.byType(TextField).first, 'short');
      await tester.enterText(find.byType(TextField).last, 'short');
      await tester.tap(filled('Continue'));
      await tester.pump();

      expect(bootstrap.calls, isEmpty);
      expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .decoration!
            .errorText,
        isNotNull,
      );
    });

    testWidgets('a phrase that is not repeated exactly is refused', (
      tester,
    ) async {
      final bootstrap = await pump(
        tester,
        BootstrapState.askNewSsss,
        mode: SecureBackupMode.phrase,
      );

      await tester.enterText(
        find.byType(TextField).first,
        'a quiet blue harbour at dawn',
      );
      await tester.enterText(
        find.byType(TextField).last,
        'a quiet blue harbour at dusk',
      );
      await tester.tap(filled('Continue'));
      await tester.pump();

      expect(bootstrap.calls, isEmpty);
      expect(find.text("That doesn't match the phrase above"), findsOneWidget);
    });

    testWidgets('a good phrase, repeated, becomes the recovery secret', (
      tester,
    ) async {
      final bootstrap = await pump(
        tester,
        BootstrapState.askNewSsss,
        mode: SecureBackupMode.phrase,
      );

      for (final field in [
        find.byType(TextField).first,
        find.byType(TextField).last,
      ]) {
        await tester.enterText(field, 'a quiet blue harbour at dawn');
      }
      await tester.tap(filled('Continue'));
      await tester.pump();

      expect(bootstrap.calls, ['newSsss(a quiet blue harbour at dawn)']);
    });

    testWidgets('with the keyboard open the phrase step does not overflow '
        'and Continue stays above it', (tester) async {
      await pump(
        tester,
        BootstrapState.askNewSsss,
        mode: SecureBackupMode.phrase,
        keyboard: 300,
      );

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(TextField).last);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(filled('Continue')).bottom,
        lessThanOrEqualTo(640 - 300),
      );
    });
  });

  group('entering an existing recovery code', () {
    testWidgets('Unlock waits for something to be typed', (tester) async {
      await pump(
        tester,
        BootstrapState.openExistingSsss,
        prepare: (b) => b.newSsssKey = _FakeKey(accepts: 'right'),
      );

      expect(find.text('Enter your recovery code'), findsOneWidget);
      expect(enabled(tester, filled('Unlock')), isFalse);

      await tester.enterText(find.byType(TextField), 'something');
      await tester.pump();
      expect(enabled(tester, filled('Unlock')), isTrue);
    });

    testWidgets('a code that does not unlock says so and stays', (
      tester,
    ) async {
      final key = _FakeKey(accepts: 'right');
      final bootstrap = await pump(
        tester,
        BootstrapState.openExistingSsss,
        prepare: (b) => b.newSsssKey = key,
      );

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.pump();
      await tester.tap(filled('Unlock'));
      await tester.pumpAndSettle();

      expect(key.attempts, ['wrong']);
      expect(bootstrap.calls, isEmpty);
      expect(
        find.text('That did not work. Check the code and try again.'),
        findsOneWidget,
      );
      expect(enabled(tester, filled('Unlock')), isTrue);
    });

    testWidgets('the right code opens the existing recovery', (tester) async {
      final bootstrap = await pump(
        tester,
        BootstrapState.openExistingSsss,
        prepare: (b) => b.newSsssKey = _FakeKey(accepts: 'right'),
      );

      await tester.enterText(find.byType(TextField), 'right');
      await tester.pump();
      await tester.tap(filled('Unlock'));
      await tester.pumpAndSettle();

      expect(bootstrap.calls, ['openExistingSsss']);
    });

    testWidgets('older secrets are unlocked one at a time, then it moves on', (
      tester,
    ) async {
      final first = _FakeKey(accepts: 'first');
      final second = _FakeKey(accepts: 'second');
      final bootstrap = await pump(
        tester,
        BootstrapState.askUnlockSsss,
        prepare: (b) => b.oldSsssKeys = {'a': first, 'b': second},
      );

      expect(find.text('Enter an older recovery code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'first');
      await tester.pump();
      await tester.tap(filled('Unlock'));
      await tester.pumpAndSettle();
      expect(bootstrap.calls, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      await tester.enterText(find.byType(TextField), 'second');
      await tester.pump();
      await tester.tap(filled('Unlock'));
      await tester.pumpAndSettle();
      expect(bootstrap.calls, ['unlockedSsss']);
    });
  });

  testWidgets('a failed setup offers to try again with a fresh start', (
    tester,
  ) async {
    await pump(tester, BootstrapState.error);

    expect(find.text('That did not work. Try again.'), findsOneWidget);
    await tester.tap(filled('Try again'));
    await tester.pump();

    expect(created, hasLength(2));
    expect(find.text('Setting up…'), findsOneWidget);
  });

  group('when setup is done', () {
    testWidgets('the twelve-word path just says so, and Done leaves', (
      tester,
    ) async {
      await pump(tester, BootstrapState.done);

      expect(find.text('All set'), findsOneWidget);
      expect(find.text('Your messages are protected.'), findsOneWidget);
      await tester.tap(filled('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(SecureBackupPage), findsNothing);
    });

    testWidgets('a generated key is shown once, and Done waits for the '
        'saved-it checkbox, both in view', (tester) async {
      await pump(
        tester,
        BootstrapState.done,
        mode: SecureBackupMode.key,
        prepare: (b) =>
            b.newSsssKey = _FakeKey(recoveryKey: 'EsTc 1234 abcd 5678 wxyz'),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Save your recovery key'), findsOneWidget);
      expect(find.text('EsTc 1234 abcd 5678 wxyz'), findsOneWidget);
      expect(enabled(tester, filled('Done')), isFalse);

      final checkbox = find.byType(CheckboxListTile);
      expect(
        find.ancestor(of: checkbox, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(
        tester.getRect(checkbox).bottom,
        lessThanOrEqualTo(tester.getRect(filled('Done')).top),
      );
      expect(
        tester.getRect(filled('Done')).bottom,
        lessThanOrEqualTo(640 - 48),
      );

      await tester.tap(checkbox);
      await tester.pump();
      expect(enabled(tester, filled('Done')), isTrue);

      await tester.tap(filled('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(SecureBackupPage), findsNothing);
    });
  });

  testWidgets('every question screen uses the shared step layout', (
    tester,
  ) async {
    for (final state in [
      BootstrapState.askWipeSsss,
      BootstrapState.askBadSsss,
      BootstrapState.done,
    ]) {
      await tester.pumpWidget(const SizedBox());
      await pump(tester, state);
      expect(find.byType(StepLayout), findsOneWidget, reason: '$state');
      expect(tester.takeException(), isNull, reason: '$state');
    }
  });
}
