import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/registration_support.dart';
import '../../../core/matrix/server_name.dart';
import '../../../core/matrix/session_display_name.dart';
import '../../../core/matrix/username_field.dart';
import '../../../core/ui/keyboard.dart';
import 'auth_scaffold.dart';
import 'homeserver_page.dart';
import 'linked_sign_in_page.dart';
import 'password_field.dart';
import 'register_page.dart';
import 'registration_code_page.dart';
import 'retry_wait.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with RetryWait<LoginPage>, PasswordReveal<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || waitingToRetry) return;
    closeKeyboard();
    final client = ref.read(matrixClientProvider);
    final username = _username.text.trim();

    if (username.isEmpty) {
      setState(() => _error = 'Enter your username');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: _password.text,
        initialDeviceDisplayName: sessionDisplayName(Platform.operatingSystem),
        refreshToken: true,
      );
      TextInput.finishAutofillContext();
      if (!mounted) return;

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = loginErrorMessage(e));
      holdRetriesFor(e, whenOver: () => _error = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Widget page) {
    closeKeyboard();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _createAccountPage(RegistrationSupport? registration) {
    if (registration?.requiresRegistrationToken ?? false) {
      return const RegistrationCodePage();
    }
    return const RegisterPage();
  }

  @override
  Widget build(BuildContext context) {
    final serverName = ref.watch(serverNameProvider);
    final registration = ref.watch(registrationSupportProvider).value;

    return AuthScaffold(
      title: 'Sign in',
      footer: [
        if (registration?.isAvailable ?? false)
          OutlinedButton(
            onPressed: _loading
                ? null
                : () => _open(_createAccountPage(registration)),
            child: const Text('Create account'),
          ),
        if (serverName != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  serverName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => _open(const HomeserverPage()),
                child: const Text('Change'),
              ),
            ],
          ),
      ],
      children: [
        AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _username,
                enabled: !_loading,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.username],
                inputFormatters: [lowercaseFormatter],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Username',
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
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
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
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loading || waitingToRetry ? null : _login,
          child: Text(_loading ? 'Signing in…' : 'Sign in'),
        ),
        TextButton(
          onPressed: _loading ? null : () => _open(const LinkedSignInPage()),
          child: const Text('Sign in with your other device'),
        ),
      ],
    );
  }
}
