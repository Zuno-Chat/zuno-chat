import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInput, TextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/homeserver.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/registration_support.dart';
import '../../../core/matrix/server_name.dart';
import '../../../core/matrix/session_display_name.dart';
import '../../../core/matrix/username_field.dart';
import '../../../core/navigation/zuno_links.dart';
import '../../../core/onboarding/onboarding_provider.dart';
import '../../../core/security/screen_security_service.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/inline_feedback.dart';
import '../../../core/ui/keyboard.dart';
import 'auth_scaffold.dart';
import 'password_field.dart';
import 'password_strength_bar.dart';
import 'retry_wait.dart';

class RegisterPage extends ConsumerStatefulWidget {
  final bool requiresCode;
  final String? email;
  final UrlOpener openUrl;

  const RegisterPage({
    super.key,
    this.requiresCode = false,
    this.email,
    this.openUrl = openExternally,
  });

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage>
    with
        RetryWait<RegisterPage>,
        PasswordReveal<RegisterPage>,
        AccessibilityServicesAllowed<RegisterPage> {
  final _code = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _loading = false;
  bool _codeRefused = false;
  String? _error;
  (String, String, String?)? _progressInputs;
  var _progress = RegistrationProgress();

  @override
  void dispose() {
    _code.dispose();
    _username.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _clearError() {
    if (waitingToRetry || (_error == null && !_codeRefused)) return;
    setState(() {
      _error = null;
      _codeRefused = false;
    });
  }

  Future<void> _register() async {
    if (_loading || waitingToRetry) return;
    closeKeyboard();
    final client = ref.read(matrixClientProvider);
    final onboarding = ref.read(onboardingStoreProvider);
    final l10n = context.l10n;
    final username = _username.text.trim();
    final password = _password.text;
    final code = widget.requiresCode ? _code.text.trim() : null;

    if (code != null && code.isEmpty) {
      setState(() => _error = l10n.authEnterEmailCode);
      return;
    }
    final inputError = registrationInputError(
      l10n,
      username: username,
      password: password,
      confirmPassword: _confirmPassword.text,
      serverName: ref.read(serverNameProvider),
    );
    if (inputError != null) {
      setState(() => _error = inputError);
      return;
    }

    final inputs = (username, password, code);
    if (_progressInputs != inputs) {
      _progressInputs = inputs;
      _progress = RegistrationProgress();
    }

    setState(() {
      _loading = true;
      _codeRefused = false;
      _error = null;
    });

    try {
      await ref.read(signInInFlightProvider.notifier).during(() async {
        await runRegistration(
          client,
          username: username,
          password: password,
          code: code,
          deviceDisplayName: thisSessionDisplayName(),
          progress: _progress,
        );
        final userId = client.userID;
        if (userId != null) await onboarding.markRegistered(userId);
      });
      TextInput.finishAutofillContext();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on RegistrationCodeRefusedException catch (e) {
      if (!mounted) return;
      setState(() {
        _codeRefused = true;
        _error = registrationErrorMessage(l10n, e);
      });
    } catch (e, s) {
      if (!isRegistrationRefusal(e)) reportCaught('register', e, s);
      if (!mounted) return;
      setState(() => _error = registrationErrorMessage(l10n, e));
      holdRetriesFor(e, whenOver: () => _error = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Uri uri) =>
      openLink(context, uri, openUrl: widget.openUrl);

  @override
  Widget build(BuildContext context) {
    final serverName = ref.watch(serverNameProvider);
    final onZuno = serverName == officialHomeserver.host;
    final l10n = context.l10n;

    return PopScope(
      canPop: !_loading,
      child: AuthScaffold(
        title: l10n.authCreateYourAccount,
        footer: [
          if (onZuno) ...[
            Text(
              l10n.authRegisterAgreement,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _open(termsUri),
                  child: Text(l10n.commonTerms),
                ),
                TextButton(
                  onPressed: () => _open(privacyPolicyUri),
                  child: Text(l10n.commonPrivacyPolicy),
                ),
              ],
            ),
          ],
        ],
        children: [
          if (serverName != null) ...[
            Text(
              l10n.authAccountLivesOn(serverName),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.email case final email?) ...[
            Text(
              l10n.authCheckEmailForCode(email),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.requiresCode) ...[
            ZunoTextField(
              autofillHints: null,
              controller: _code,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => _clearError(),
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (_, value) => value.copyWith(text: value.text.toUpperCase()),
                ),
                FilteringTextInputFormatter.allow(RegExp(r'[A-HJ-NP-Z2-9]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.authSignUpCodeLabel,
                helperText: l10n.authSignUpCodeHelper,
              ),
            ),
            const SizedBox(height: 16),
          ],
          AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ZunoTextField(
                  controller: _username,
                  enabled: !_loading,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [
                    AutofillHints.newUsername,
                    AutofillHints.username,
                  ],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _clearError(),
                  inputFormatters: [lowercaseFormatter, usernameCharsFormatter],
                  decoration: InputDecoration(
                    labelText: l10n.commonUsername,
                    helperText: l10n.authRegisterUsernameHelper,
                  ),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _password,
                  labelText: l10n.commonPassword,
                  enabled: !_loading,
                  revealed: passwordRevealed,
                  onToggleReveal: togglePasswordReveal,
                  autofillHints: const [
                    AutofillHints.newPassword,
                    AutofillHints.password,
                  ],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _clearError(),
                ),
                ListenableBuilder(
                  listenable: Listenable.merge([_password, _username]),
                  builder: (context, _) => PasswordStrengthBar(
                    password: _password.text,
                    username: _username.text.trim(),
                  ),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _confirmPassword,
                  labelText: l10n.authConfirmPasswordLabel,
                  enabled: !_loading,
                  revealed: passwordRevealed,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _clearError(),
                  onSubmitted: (_) => _register(),
                ),
              ],
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 16),
            InlineError(error),
          ],
          if (_codeRefused) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loading ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.authSendNewCode),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading || waitingToRetry ? null : _register,
            child: Text(
              _loading ? l10n.authCreatingAccount : l10n.authCreateAccount,
            ),
          ),
        ],
      ),
    );
  }
}
