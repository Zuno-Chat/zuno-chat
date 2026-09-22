import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInput, TextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/homeserver.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/registration_support.dart';
import '../../../core/matrix/server_name.dart';
import '../../../core/matrix/session_display_name.dart';
import '../../../core/matrix/username_field.dart';
import '../../../core/navigation/zuno_links.dart';
import '../../../core/onboarding/onboarding_provider.dart';
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
    with RetryWait<RegisterPage>, PasswordReveal<RegisterPage> {
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
    if (waitingToRetry) return;
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
    final username = _username.text.trim();
    final password = _password.text;
    final code = widget.requiresCode ? _code.text.trim() : null;

    if (code != null && code.isEmpty) {
      setState(() => _error = 'Enter the code from your email');
      return;
    }
    final inputError = registrationInputError(
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
      await runRegistration(
        client,
        username: username,
        password: password,
        code: code,
        deviceDisplayName: sessionDisplayName(Platform.operatingSystem),
        progress: _progress,
      );
      final userId = client.userID;
      if (userId != null) {
        await onboarding.markRegistered(userId);
      }
      TextInput.finishAutofillContext();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on RegistrationCodeRefusedException catch (e) {
      if (!mounted) return;
      setState(() {
        _codeRefused = true;
        _error = registrationErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = registrationErrorMessage(e));
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

    return AuthScaffold(
      title: 'Create your account',
      footer: [
        if (onZuno) ...[
          Text(
            'Creating an account means you agree to the terms and the privacy '
            'policy.',
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
                child: const Text('Terms'),
              ),
              TextButton(
                onPressed: () => _open(privacyPolicyUri),
                child: const Text('Privacy policy'),
              ),
            ],
          ),
        ],
      ],
      children: [
        if (serverName != null) ...[
          Text(
            'Your account lives on $serverName.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (widget.email != null) ...[
          Text(
            'Check ${widget.email} for your code. It expires in 24 hours.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (widget.requiresCode) ...[
          TextField(
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
            decoration: const InputDecoration(
              labelText: 'Sign-up code',
              helperText: 'From the email Zuno sent',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
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
                decoration: const InputDecoration(
                  labelText: 'Username',
                  helperText: 'Letters, numbers, dots and underscores',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                labelText: 'Password',
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
              PasswordStrengthBar(
                password: _password.text,
                username: _username.text.trim(),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirmPassword,
                labelText: 'Confirm password',
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
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_codeRefused) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: const Text('Send a new code'),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loading || waitingToRetry ? null : _register,
          child: Text(_loading ? 'Creating account…' : 'Create account'),
        ),
      ],
    );
  }
}
