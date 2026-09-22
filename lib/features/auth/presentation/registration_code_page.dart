import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/registration_code_request.dart';
import '../../../core/ui/keyboard.dart';
import 'auth_scaffold.dart';
import 'register_page.dart';

class RegistrationCodePage extends ConsumerStatefulWidget {
  const RegistrationCodePage({super.key});

  @override
  ConsumerState<RegistrationCodePage> createState() =>
      _RegistrationCodePageState();
}

class _RegistrationCodePageState extends ConsumerState<RegistrationCodePage> {
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    closeKeyboard();
    final email = _email.text.trim();
    if (!looksLikeEmail(email)) {
      setState(
        () => _error = registrationCodeErrorMessage(
          RegistrationCodeOutcome.invalidEmail,
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    RegistrationCodeOutcome outcome;
    try {
      outcome = await requestRegistrationCode(
        ref.read(matrixClientProvider),
        email,
      );
    } catch (_) {
      outcome = RegistrationCodeOutcome.serverError;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (outcome != RegistrationCodeOutcome.sent) {
      setState(() => _error = registrationCodeErrorMessage(outcome));
      return;
    }
    _openRegisterPage(email);
  }

  void _openRegisterPage(String? email) {
    closeKeyboard();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegisterPage(requiresCode: true, email: email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Get a sign-up code',
      footer: [
        TextButton(
          onPressed: _loading ? null : () => _openRegisterPage(null),
          child: const Text('I already have a code'),
        ),
      ],
      children: [
        Text(
          'Zuno sends a single-use code to your email address to keep '
          'automated sign-ups out. The address is used only to send the code '
          'and to limit how often codes are requested. It is not stored with '
          'your account.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          enabled: !_loading,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _send(),
          decoration: const InputDecoration(
            labelText: 'Email address',
            border: OutlineInputBorder(),
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
          onPressed: _loading ? null : _send,
          child: Text(_loading ? 'Sending code…' : 'Send code'),
        ),
      ],
    );
  }
}
