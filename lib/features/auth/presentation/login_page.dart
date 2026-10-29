import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/registration_support.dart';
import '../../../core/matrix/server_name.dart';
import '../../../core/matrix/session_display_name.dart';
import '../../../core/matrix/username_field.dart';
import '../../../core/security/screen_security_service.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/inline_feedback.dart';
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
    with
        RetryWait<LoginPage>,
        PasswordReveal<LoginPage>,
        AccessibilityServicesAllowed<LoginPage> {
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
      setState(() => _error = context.l10n.authEnterUsername);
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = context.l10n.authEnterPassword);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref
          .read(signInInFlightProvider.notifier)
          .during(
            () => client.login(
              LoginType.mLoginPassword,
              identifier: AuthenticationUserIdentifier(user: username),
              password: _password.text,
              initialDeviceDisplayName: thisSessionDisplayName(),
              refreshToken: true,
            ),
          );
      TextInput.finishAutofillContext();
    } catch (e, s) {
      if (!isLoginRefusal(e)) reportCaught('sign in', e, s);
      if (!mounted) return;
      setState(() => _error = loginErrorMessage(context.l10n, e));
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
    final l10n = context.l10n;

    return AuthScaffold(
      title: l10n.authSignIn,
      footer: [
        if (registration?.isAvailable ?? false)
          OutlinedButton(
            onPressed: _loading
                ? null
                : () => _open(_createAccountPage(registration)),
            child: Text(l10n.authCreateAccount),
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
                child: Text(l10n.authChangeServer),
              ),
            ],
          ),
      ],
      children: [
        AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ZunoTextField(
                controller: _username,
                enabled: !_loading,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.username],
                inputFormatters: [lowercaseFormatter],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: l10n.commonUsername),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                labelText: l10n.commonPassword,
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
        if (_error case final error?) ...[
          const SizedBox(height: 16),
          InlineError(error),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loading || waitingToRetry ? null : _login,
          child: Text(_loading ? l10n.authSigningIn : l10n.authSignIn),
        ),
        TextButton(
          onPressed: _loading ? null : () => _open(const LinkedSignInPage()),
          child: Text(l10n.authSignInWithOtherDevice),
        ),
      ],
    );
  }
}
