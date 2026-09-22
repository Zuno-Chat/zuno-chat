import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/force_sync.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/security/password_strength.dart';
import '../../../core/security/prepared_uia_password.dart';
import '../../../core/security/recovery_code.dart';
import '../../../core/security/reset_confirmations.dart';
import '../../../core/security/restore_key_backup.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/sensitive_clipboard.dart';
import '../../../core/ui/step_hero.dart';
import '../../../core/ui/step_layout.dart';
import '../../../core/ui/zuno_theme.dart';
import '../../auth/presentation/password_strength_bar.dart';
import 'recovery_code_screens.dart';
import 'uia_password_prompt.dart';

enum SecureBackupMode { recoveryCode, key, phrase }

typedef BootstrapFactory = Bootstrap Function(
  Client client,
  void Function(Bootstrap) onUpdate,
);

Bootstrap _sdkBootstrap(Client client, void Function(Bootstrap) onUpdate) =>
    Bootstrap(encryption: client.encryption!, onUpdate: onUpdate);

const _buttonSpinner = SizedBox(
  width: 20,
  height: 20,
  child: CircularProgressIndicator(strokeWidth: 2),
);

class SecureBackupPage extends ConsumerStatefulWidget {
  final SecureBackupMode mode;
  final bool? autoRestoreExisting;
  final BootstrapFactory createBootstrap;

  const SecureBackupPage({
    this.mode = SecureBackupMode.recoveryCode,
    this.autoRestoreExisting,
    this.createBootstrap = _sdkBootstrap,
    super.key,
  });

  @override
  ConsumerState<SecureBackupPage> createState() => _SecureBackupPageState();
}

class _SecureBackupPageState extends ConsumerState<SecureBackupPage> {
  Bootstrap? _bootstrap;
  StreamSubscription<UiaRequest>? _uiaSub;

  bool _wipeExisting = true;
  final _recoveryKeyInputController = TextEditingController();
  String? _recoveryKeyInputError;
  bool _busy = false;
  final _preparedUiaPassword = PreparedUiaPassword();
  bool _askingForPassword = false;
  bool _syncedAfterDone = false;

  @override
  void initState() {
    super.initState();
    final client = ref.read(matrixClientProvider);
    _uiaSub = client.onUiaRequest.stream.listen(_handleUia);
    _bootstrap = widget.createBootstrap(client, _onBootstrapUpdate);
    _maybeAutoAdvance();
  }

  @override
  void dispose() {
    _uiaSub?.cancel();
    _recoveryKeyInputController.dispose();
    super.dispose();
  }

  void _onBootstrapUpdate(Bootstrap bootstrap) {
    if (bootstrap.state == BootstrapState.error) {
      logCaught(
        'recovery bootstrap',
        bootstrap.errorResult?.error ?? 'unknown',
      );
    }
    if (!mounted) return;
    setState(() {});
    _maybeAutoAdvance();

    if (bootstrap.state == BootstrapState.done && !_syncedAfterDone) {
      _syncedAfterDone = true;
      unawaited(_restoreThenRefresh(ref.read(matrixClientProvider)));
      if (_wipeExisting) {
        unawaited(
          forgetConfirmationsAfterIdentityReset(
            ref.read(matrixClientProvider),
            ref.read(confirmedIdentityStoreProvider),
          ),
        );
      }
    }
  }

  Future<void> _restoreThenRefresh(Client client) async {
    await restoreKeyBackupFromRecovery(client);
    await runBestEffort(
      () => forceSyncNow(client),
      label: 'forceSyncNow after recovery',
    );
  }

  void _maybeAutoAdvance() {
    final b = _bootstrap;
    if (b == null) return;
    switch (b.state) {
      case BootstrapState.askWipeSsss:
        final autoRestore = widget.autoRestoreExisting;
        if (autoRestore == null) break;
        if (autoRestore) {
          setState(() => _wipeExisting = false);
          b.wipeSsss(false);
        } else {
          unawaited(_replaceExistingRecovery(b));
        }
      case BootstrapState.askUseExistingSsss:
        b.useExistingSsss(true);
      case BootstrapState.askWipeCrossSigning:
        b.wipeCrossSigning(_wipeExisting);
      case BootstrapState.askSetupCrossSigning:
        b.askSetupCrossSigning(
          setupMasterKey: true,
          setupSelfSigningKey: true,
          setupUserSigningKey: true,
        );
      case BootstrapState.askWipeOnlineKeyBackup:
        b.wipeOnlineKeyBackup(_wipeExisting);
      case BootstrapState.askSetupOnlineKeyBackup:
        b.askSetupOnlineKeyBackup(true);
      default:
        break;
    }
  }

  Future<void> _handleUia(UiaRequest uia) async {
    if (uia.state != UiaRequestState.waitForUser) return;
    final client = ref.read(matrixClientProvider);
    final password =
        _preparedUiaPassword.take() ?? await askPasswordForUia(context);
    if (!mounted) return;
    if (password == null || password.isEmpty) {
      uia.cancel();
      return;
    }
    await uia.completeStage(
      AuthenticationPassword(
        session: uia.session,
        password: password,
        identifier: AuthenticationUserIdentifier(user: client.userID!),
      ),
    );
  }

  Future<void> _replaceExistingRecovery(Bootstrap bootstrap) async {
    if (_askingForPassword) return;
    _askingForPassword = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final password = await askPasswordForUia(context);
      if (!mounted) return;
      if (password == null || password.isEmpty) return;
      _preparedUiaPassword.prepare(password);
      setState(() => _wipeExisting = true);
      bootstrap.wipeSsss(true);
    } finally {
      _askingForPassword = false;
    }
  }

  void _restart() {
    setState(() {
      _wipeExisting = true;
      _preparedUiaPassword.clear();
      _recoveryKeyInputController.clear();
      _recoveryKeyInputError = null;
      _bootstrap = widget.createBootstrap(
        ref.read(matrixClientProvider),
        _onBootstrapUpdate,
      );
    });
  }

  String _unlockInput() => recoveryUnlockInput(
    _recoveryKeyInputController.text,
    ref.read(recoveryWordlistProvider).value,
  );

  Future<void> _unlockWithEnteredKey() async {
    final key = _bootstrap?.newSsssKey;
    if (key == null) return;
    setState(() {
      _busy = true;
      _recoveryKeyInputError = null;
    });
    try {
      await key.unlock(keyOrPassphrase: _unlockInput());
      if (!mounted) return;
      await _bootstrap!.openExistingSsss();
    } catch (e) {
      logCaught('unlock recovery', e);
      if (!mounted) return;
      setState(
        () => _recoveryKeyInputError =
            'That did not work. Check the code and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  OpenSSSS? _nextLockedOldKey() =>
      _bootstrap?.oldSsssKeys?.values.where((k) => !k.isUnlocked).firstOrNull;

  Future<void> _unlockNextOldKey() async {
    final key = _nextLockedOldKey();
    if (key == null) {
      _bootstrap?.unlockedSsss();
      return;
    }
    setState(() {
      _busy = true;
      _recoveryKeyInputError = null;
    });
    try {
      await key.unlock(keyOrPassphrase: _unlockInput());
      if (!mounted) return;
      _recoveryKeyInputController.clear();
      if (_nextLockedOldKey() == null) {
        _bootstrap?.unlockedSsss();
      }
    } catch (e) {
      logCaught('unlock older recovery', e);
      if (!mounted) return;
      setState(
        () => _recoveryKeyInputError =
            'That did not work. Check the code and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newSsss(Bootstrap bootstrap, [String? passphrase]) async {
    setState(() => _busy = true);
    try {
      await bootstrap.newSsss(passphrase);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = _bootstrap;
    return Scaffold(
      appBar: AppBar(title: const Text('Recovery')),
      body: bootstrap == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: _body(context, bootstrap)),
    );
  }

  Widget _body(BuildContext context, Bootstrap bootstrap) {
    switch (bootstrap.state) {
      case BootstrapState.loading:
      case BootstrapState.askUseExistingSsss:
      case BootstrapState.askWipeCrossSigning:
      case BootstrapState.askSetupCrossSigning:
      case BootstrapState.askWipeOnlineKeyBackup:
      case BootstrapState.askSetupOnlineKeyBackup:
        return const _StatusScreen(message: 'Setting up…');

      case BootstrapState.askWipeSsss:
        return _ChoiceScreen(
          icon: Icons.backup_outlined,
          title: 'This account already has recovery set up',
          body:
              'Another device set it up. Enter that code to unlock your '
              'messages here, or start over with a new one. Starting over '
              'stops the old code working, your other devices need approving '
              'again, and anyone you have confirmed needs confirming again.',
          primaryLabel: 'Enter recovery code',
          onPrimary: () {
            setState(() => _wipeExisting = false);
            bootstrap.wipeSsss(false);
          },
          secondaryLabel: 'Start over with a new code',
          onSecondary: () => unawaited(_replaceExistingRecovery(bootstrap)),
        );

      case BootstrapState.askBadSsss:
        return _ChoiceScreen(
          icon: Icons.warning_amber_outlined,
          title: 'Some recovery data cannot be read',
          body:
              'Part of the recovery data on this account is unreadable. '
              'Continue to set up fresh recovery, leaving the unreadable parts '
              'as they are, or cancel.',
          primaryLabel: 'Continue anyway',
          onPrimary: () => bootstrap.ignoreBadSecrets(true),
          secondaryLabel: 'Cancel',
          onSecondary: () => Navigator.of(context).pop(),
        );

      case BootstrapState.askNewSsss:
        switch (widget.mode) {
          case SecureBackupMode.recoveryCode:
            return RecoveryCodeCreateFlow(
              busy: _busy,
              onComplete: (code) => _newSsss(bootstrap, code),
            );
          case SecureBackupMode.phrase:
            return _PhraseInputScreen(
              busy: _busy,
              onSubmit: (phrase) => _newSsss(bootstrap, phrase),
            );
          case SecureBackupMode.key:
            return _ChoiceScreen(
              icon: Icons.key_outlined,
              title: 'Create a security key',
              body:
                  "This generates a security key that unlocks your account's "
                  'encrypted history on a new device, and lets other devices '
                  "trust each other automatically. You'll see it once, right "
                  'after — save it somewhere safe, like a password manager.',
              primaryLabel: 'Generate security key',
              busy: _busy,
              onPrimary: () => _newSsss(bootstrap),
            );
        }

      case BootstrapState.openExistingSsss:
        return _RecoveryKeyInputScreen(
          title: 'Enter your recovery code',
          subtitle:
              'The words you saved when recovery was set up. A security key or '
              'phrase from another app works here too.',
          controller: _recoveryKeyInputController,
          error: _recoveryKeyInputError,
          busy: _busy,
          onSubmit: _unlockWithEnteredKey,
        );

      case BootstrapState.askUnlockSsss:
        return _RecoveryKeyInputScreen(
          title: 'Enter an older recovery code',
          subtitle:
              'This account has more than one old recovery secret on file. '
              'Enter each one to migrate it.',
          controller: _recoveryKeyInputController,
          error: _recoveryKeyInputError,
          busy: _busy,
          onSubmit: _unlockNextOldKey,
        );

      case BootstrapState.error:
        return _StatusScreen(
          message: 'That did not work. Try again.',
          action: FilledButton(
            onPressed: _restart,
            child: const Text('Try again'),
          ),
        );

      case BootstrapState.done:
        return _DoneScreen(
          recoveryKey: widget.mode == SecureBackupMode.recoveryCode
              ? null
              : bootstrap.newSsssKey?.recoveryKey,
          wasRestore: !_wipeExisting,
        );
    }
  }
}

class _StatusScreen extends StatelessWidget {
  final String message;
  final Widget? action;
  const _StatusScreen({required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

class _ChoiceScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool busy;

  const _ChoiceScreen({
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return StepLayout(
      hero: StepHero(icon: icon),
      title: title,
      body: body,
      actions: [
        FilledButton(
          onPressed: busy ? null : onPrimary,
          child: busy ? _buttonSpinner : Text(primaryLabel),
        ),
        if (secondaryLabel != null)
          TextButton(
            onPressed: busy ? null : onSecondary,
            child: Text(secondaryLabel!),
          ),
      ],
    );
  }
}

class _RecoveryKeyInputScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final TextEditingController controller;
  final String? error;
  final bool busy;
  final VoidCallback onSubmit;

  const _RecoveryKeyInputScreen({
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.error,
    required this.busy,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return StepLayout(
      hero: const StepHero(icon: Icons.key_outlined, compact: true),
      title: title,
      body: subtitle,
      actions: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => FilledButton(
            onPressed: busy || value.text.trim().isEmpty ? null : onSubmit,
            child: busy ? _buttonSpinner : const Text('Unlock'),
          ),
        ),
      ],
      children: [
        RecoveryCodeEntryField(
          controller: controller,
          error: error,
          busy: busy,
          onSubmit: onSubmit,
        ),
      ],
    );
  }
}

class _PhraseInputScreen extends StatefulWidget {
  final bool busy;
  final ValueChanged<String> onSubmit;
  const _PhraseInputScreen({required this.busy, required this.onSubmit});

  @override
  State<_PhraseInputScreen> createState() => _PhraseInputScreenState();
}

class _PhraseInputScreenState extends State<_PhraseInputScreen> {
  final _phraseController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _phraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final phrase = _phraseController.text;
    final assessment = assessPassword(phrase);
    if (assessment.blocker != null) {
      setState(() => _error = assessment.blocker);
      return;
    }
    if (phrase != _confirmController.text) {
      setState(() => _error = "That doesn't match the phrase above");
      return;
    }
    setState(() => _error = null);
    widget.onSubmit(phrase);
  }

  @override
  Widget build(BuildContext context) {
    return StepLayout(
      hero: const StepHero(icon: Icons.password_outlined, compact: true),
      title: 'Choose a security phrase',
      body:
          "Pick a secret phrase only you know — you'll need it to unlock "
          "encrypted history on a new device. This also generates a backup "
          "security key, shown once right after, in case you forget the "
          "phrase.",
      actions: [
        FilledButton(
          onPressed: widget.busy ? null : _submit,
          child: widget.busy ? _buttonSpinner : const Text('Continue'),
        ),
      ],
      children: [
        TextField(
          autofillHints: null,
          controller: _phraseController,
          autofocus: true,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Security phrase'),
        ),
        const SizedBox(height: 12),
        TextField(
          autofillHints: null,
          controller: _confirmController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Confirm security phrase',
            errorText: _error,
          ),
          onSubmitted: (_) => widget.busy ? null : _submit(),
        ),
        PasswordStrengthBar(password: _phraseController.text),
      ],
    );
  }
}

class _DoneScreen extends StatefulWidget {
  final String? recoveryKey;
  final bool wasRestore;
  const _DoneScreen({required this.recoveryKey, required this.wasRestore});

  @override
  State<_DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends State<_DoneScreen> {
  bool _savedConfirmed = false;

  @override
  Widget build(BuildContext context) {
    final recoveryKey = widget.wasRestore ? null : widget.recoveryKey;
    if (recoveryKey == null) {
      return StepLayout(
        hero: const StepHero(icon: Icons.check_circle_outline),
        title: widget.wasRestore ? 'Restored' : 'All set',
        body: 'Your messages are protected.',
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      );
    }

    return StepLayout(
      hero: const StepHero(icon: Icons.key_outlined, compact: true),
      title: 'Save your recovery key',
      body:
          "This is the only time you'll see it. Store it somewhere safe — a "
          "password manager works well. You'll need it to restore encrypted "
          "history on any future device.",
      actions: [
        CheckboxListTile(
          value: _savedConfirmed,
          onChanged: (v) => setState(() => _savedConfirmed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text("I've saved my recovery key"),
        ),
        FilledButton(
          onPressed: _savedConfirmed ? () => Navigator.of(context).pop() : null,
          child: const Text('Done'),
        ),
      ],
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(ZunoRadius.small),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  recoveryKey,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copy',
                onPressed: () {
                  SensitiveClipboard.instance.copy(recoveryKey);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied — clears in 90 seconds'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
