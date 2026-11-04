import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/auth_browser.dart';
import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/homeserver.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/oauth_sign_in.dart';
import '../../../core/matrix/server_choice.dart';
import '../../../core/matrix/server_name.dart';
import '../../../core/matrix/session_display_name.dart';
import '../../../core/matrix/username_field.dart';
import '../../../core/onboarding/onboarding_provider.dart';
import '../../../core/security/screen_security_service.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/inline_feedback.dart';
import '../../../core/ui/keyboard.dart';
import '../../../core/ui/retry_wait.dart';
import 'auth_scaffold.dart';
import 'homeserver_page.dart';
import 'linked_sign_in_page.dart';
import 'password_field.dart';
import 'register_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with RetryWait<LoginPage>, PasswordReveal<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _signingIn = false;
  ServerChoice? _askingSignUpOf;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null && !waitingToRetry) setState(() => _error = null);
  }

  void _open(Widget page) {
    closeKeyboard();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _signIn() async {
    if (_signingIn || waitingToRetry) return;
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
      _signingIn = true;
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
      holdRetriesFor(retryWaitFor(e), whenOver: () => _error = null);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signInInBrowser({bool createAccount = false}) async {
    if (_signingIn || waitingToRetry) return;
    final client = ref.read(matrixClientProvider);
    final browser = ref.read(authBrowserProvider);
    final onboarding = ref.read(onboardingStoreProvider);
    final server = ref.read(serverNameProvider) ?? '';
    final l10n = context.l10n;

    setState(() {
      _signingIn = true;
      _error = null;
    });

    try {
      final grant = await authorizeInBrowser(
        client,
        browser: browser,
        createAccount: createAccount,
      );
      await ref.read(signInInFlightProvider.notifier).during(() async {
        await completeOAuthSignIn(
          client,
          grant,
          deviceDisplayName: thisSessionDisplayName(),
        );
        final userId = client.userID;
        if (createAccount && userId != null) {
          await onboarding.markRegistered(
            userId,
            nameChosen: await nameChosenAtSignUp(client),
          );
        }
      });
    } catch (e, s) {
      if (isOAuthSignInCancel(e)) return;
      if (!isExpectedOAuthSignInFailure(e)) {
        reportCaught('sign in with the browser', e, s);
      }
      if (!mounted) return;
      setState(() => _error = oauthSignInErrorMessage(l10n, e, server: server));
      holdRetriesFor(retryWaitFor(e), whenOver: () => _error = null);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _createAccount(ServerChoice server, SignUpPath shown) async {
    final path = shown == SignUpPath.unknown
        ? await _askSignUpPath(server)
        : shown;
    if (path == null || !mounted) return;
    final l10n = context.l10n;
    switch (path) {
      case SignUpPath.open:
        _open(const RegisterPage());
      case SignUpPath.code:
        _open(const RegisterPage(requiresCode: true));
      case SignUpPath.oauth:
        await _signInInBrowser(createAccount: true);
      case SignUpPath.closed:
        setState(() => _error = l10n.matrixCodeUnavailable);
      case SignUpPath.unknown:
        setState(() => _error = l10n.matrixHomeserverUnreachable);
    }
  }

  Future<SignUpPath?> _askSignUpPath(ServerChoice server) async {
    closeKeyboard();
    _clearError();
    setState(() => _askingSignUpOf = server);
    try {
      final answer = await ref.refresh(signUpPathProvider(server).future);
      if (!mounted || ref.read(homeserverProvider).value != server) return null;
      return answer;
    } finally {
      if (mounted && _askingSignUpOf == server) {
        setState(() => _askingSignUpOf = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(homeserverProvider, (_, _) {
      releaseRetryHold();
      _clearError();
    });
    final serverName = ref.watch(serverNameProvider);
    final server = ref.watch(homeserverProvider).value;
    final signUpPath = server == null
        ? null
        : ref.watch(signUpPathProvider(server)).value;
    final askingSignUp = server != null && _askingSignUpOf == server;
    final signsInInBrowser = server?.signIn is OAuthSignIn;
    final l10n = context.l10n;

    return AuthScaffold(
      title: l10n.authSignIn,
      footer: [
        if (server != null &&
            signUpPath != null &&
            signUpPath != SignUpPath.closed)
          OutlinedButton(
            onPressed:
                _signingIn ||
                    askingSignUp ||
                    (signsInInBrowser && waitingToRetry)
                ? null
                : () => _createAccount(server, signUpPath),
            child: Text(
              askingSignUp ? l10n.authConnecting : l10n.authCreateAccount,
            ),
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
                onPressed: _signingIn
                    ? null
                    : () => _open(const HomeserverPage()),
                child: Text(l10n.authChangeServer),
              ),
            ],
          ),
      ],
      children: signsInInBrowser ? _browserButton() : _passwordForm(),
    );
  }

  List<Widget> _passwordForm() {
    final l10n = context.l10n;
    return [
      _AccessibilityServicesLetIn(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ZunoTextField(
                controller: _username,
                enabled: !_signingIn,
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
                enabled: !_signingIn,
                revealed: passwordRevealed,
                onToggleReveal: togglePasswordReveal,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _signIn(),
              ),
            ],
          ),
        ),
      ),
      if (_error case final error?) ...[
        const SizedBox(height: 16),
        InlineError(error),
      ],
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _signingIn || waitingToRetry ? null : _signIn,
        child: Text(_signingIn ? l10n.authSigningIn : l10n.authSignIn),
      ),
      TextButton(
        onPressed: _signingIn ? null : () => _open(const LinkedSignInPage()),
        child: Text(l10n.authSignInWithOtherDevice),
      ),
    ];
  }

  List<Widget> _browserButton() {
    final l10n = context.l10n;
    return [
      if (_error case final error?) ...[
        InlineError(error),
        const SizedBox(height: 16),
      ],
      FilledButton(
        onPressed: _signingIn || waitingToRetry ? null : _signInInBrowser,
        child: Text(_signingIn ? l10n.authSigningIn : l10n.commonContinue),
      ),
    ];
  }
}

class _AccessibilityServicesLetIn extends StatefulWidget {
  const _AccessibilityServicesLetIn({required this.child});

  final Widget child;

  @override
  State<_AccessibilityServicesLetIn> createState() =>
      _AccessibilityServicesLetInState();
}

class _AccessibilityServicesLetInState
    extends State<_AccessibilityServicesLetIn>
    with AccessibilityServicesAllowed<_AccessibilityServicesLetIn> {
  @override
  Widget build(BuildContext context) => widget.child;
}
