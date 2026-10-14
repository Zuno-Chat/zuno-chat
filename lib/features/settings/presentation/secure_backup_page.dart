import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/uia_cancel.dart';
import '../../../core/security/password_strength.dart';
import '../../../core/security/prepared_uia_password.dart';
import '../../../core/security/recovery_code.dart';
import '../../../core/security/reset_confirmations.dart';
import '../../../core/security/restore_key_backup.dart';
import '../../../core/security/secret_text.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/sensitive_clipboard.dart';
import '../../../core/security/zuno_text_field.dart';
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

bool _wrongRecoveryInput(Object error) =>
    error is InvalidPassphraseException ||
    (error is FormatException && error.message.contains('Base58'));

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
      final error = bootstrap.errorResult?.error ?? 'unknown';
      if (!isUiaCancel(error)) {
        reportCaught(
          'recovery bootstrap',
          error,
          bootstrap.errorResult?.stackTrace,
        );
      }
    }
    if (!mounted) return;
    setState(() {});
    _maybeAutoAdvance();

    if (bootstrap.state == BootstrapState.done && !_syncedAfterDone) {
      _syncedAfterDone = true;
      unawaited(restoreKeyBackupFromRecovery(ref.read(matrixClientProvider)));
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

  Future<void> _handleUia(UiaRequest uia) => answerUiaWithPassword(
    context,
    uia,
    userId: ref.read(matrixClientProvider).userID!,
    preparedPassword: _preparedUiaPassword.take,
  );

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
    } catch (e, s) {
      if (!_wrongRecoveryInput(e)) reportCaught('unlock recovery', e, s);
      if (!mounted) return;
      setState(
        () => _recoveryKeyInputError =
            context.l10n.settingsSecureBackupUnlockFailed,
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
    } catch (e, s) {
      if (!_wrongRecoveryInput(e)) reportCaught('unlock older recovery', e, s);
      if (!mounted) return;
      setState(
        () => _recoveryKeyInputError =
            context.l10n.settingsSecureBackupUnlockFailed,
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
      appBar: AppBar(title: Text(context.l10n.settingsSecureBackupTitle)),
      body: bootstrap == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: _body(context, bootstrap)),
    );
  }

  Widget _body(BuildContext context, Bootstrap bootstrap) {
    final l10n = context.l10n;
    switch (bootstrap.state) {
      case BootstrapState.loading:
      case BootstrapState.askUseExistingSsss:
      case BootstrapState.askWipeCrossSigning:
      case BootstrapState.askSetupCrossSigning:
      case BootstrapState.askWipeOnlineKeyBackup:
      case BootstrapState.askSetupOnlineKeyBackup:
        return _StatusScreen(message: l10n.settingsSecureBackupSettingUp);

      case BootstrapState.askWipeSsss:
        return _ChoiceScreen(
          icon: Icons.backup_outlined,
          title: l10n.settingsSecureBackupExistingTitle,
          body: l10n.settingsSecureBackupExistingBody,
          primaryLabel: l10n.securityEnterRecoveryCode,
          onPrimary: () {
            setState(() => _wipeExisting = false);
            bootstrap.wipeSsss(false);
          },
          secondaryLabel: l10n.settingsSecureBackupStartOver,
          onSecondary: () => unawaited(_replaceExistingRecovery(bootstrap)),
        );

      case BootstrapState.askBadSsss:
        return _ChoiceScreen(
          icon: Icons.warning_amber_outlined,
          title: l10n.settingsSecureBackupBadTitle,
          body: l10n.settingsSecureBackupBadBody,
          primaryLabel: l10n.commonContinueAnyway,
          onPrimary: () => bootstrap.ignoreBadSecrets(true),
          secondaryLabel: l10n.commonCancel,
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
              title: l10n.settingsSecureBackupCreateKeyTitle,
              body: l10n.settingsSecureBackupCreateKeyBody,
              primaryLabel: l10n.settingsSecureBackupGenerateKey,
              busy: _busy,
              onPrimary: () => _newSsss(bootstrap),
            );
        }

      case BootstrapState.openExistingSsss:
        return _RecoveryKeyInputScreen(
          title: l10n.settingsSecureBackupEnterTitle,
          subtitle: l10n.settingsSecureBackupEnterSubtitle,
          controller: _recoveryKeyInputController,
          error: _recoveryKeyInputError,
          busy: _busy,
          onSubmit: _unlockWithEnteredKey,
        );

      case BootstrapState.askUnlockSsss:
        return _RecoveryKeyInputScreen(
          title: l10n.settingsSecureBackupOlderTitle,
          subtitle: l10n.settingsSecureBackupOlderSubtitle,
          controller: _recoveryKeyInputController,
          error: _recoveryKeyInputError,
          busy: _busy,
          onSubmit: _unlockNextOldKey,
        );

      case BootstrapState.error:
        return _StatusScreen(
          message: l10n.settingsSecureBackupFailed,
          action: FilledButton(
            onPressed: _restart,
            child: Text(l10n.commonTryAgain),
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
            child: busy
                ? _buttonSpinner
                : Text(context.l10n.settingsSecureBackupUnlock),
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
    final assessment = assessPassword(context.l10n, phrase);
    if (assessment.blocker != null) {
      setState(() => _error = assessment.blocker);
      return;
    }
    if (phrase != _confirmController.text) {
      setState(() => _error = context.l10n.settingsSecureBackupPhraseMismatch);
      return;
    }
    setState(() => _error = null);
    widget.onSubmit(phrase);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StepLayout(
      hero: const StepHero(icon: Icons.password_outlined, compact: true),
      title: l10n.settingsSecureBackupPhraseTitle,
      body: l10n.settingsSecureBackupPhraseBody,
      actions: [
        FilledButton(
          onPressed: widget.busy ? null : _submit,
          child: widget.busy ? _buttonSpinner : Text(l10n.commonContinue),
        ),
      ],
      children: [
        ZunoTextField(
          autofillHints: null,
          controller: _phraseController,
          autofocus: true,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.settingsSecureBackupPhraseLabel,
          ),
        ),
        const SizedBox(height: 12),
        ZunoTextField(
          autofillHints: null,
          controller: _confirmController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.settingsSecureBackupPhraseConfirmLabel,
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
    final l10n = context.l10n;
    final recoveryKey = widget.wasRestore ? null : widget.recoveryKey;
    if (recoveryKey == null) {
      return StepLayout(
        hero: const StepHero(icon: Icons.check_circle_outline),
        title: widget.wasRestore
            ? l10n.settingsSecureBackupRestored
            : l10n.settingsSecureBackupAllSet,
        body: l10n.settingsSecureBackupProtected,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonDone),
          ),
        ],
      );
    }

    return StepLayout(
      hero: const StepHero(icon: Icons.key_outlined, compact: true),
      title: l10n.settingsSecureBackupSaveKeyTitle,
      body: l10n.settingsSecureBackupSaveKeyBody,
      actions: [
        CheckboxListTile(
          value: _savedConfirmed,
          onChanged: (v) => setState(() => _savedConfirmed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(l10n.settingsSecureBackupSavedKey),
        ),
        FilledButton(
          onPressed: _savedConfirmed ? () => Navigator.of(context).pop() : null,
          child: Text(l10n.commonDone),
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
                child: SecretText(
                  recoveryKey,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: l10n.commonCopy,
                onPressed: () {
                  SensitiveClipboard.instance.copy(recoveryKey);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.settingsSecureBackupKeyCopied)),
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
