import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/registration_code_request.dart';
import '../../../core/security/zuno_text_field.dart';
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
          context.l10n,
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
    } catch (e, s) {
      reportCaught('request registration code', e, s);
      outcome = RegistrationCodeOutcome.serverError;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (outcome != RegistrationCodeOutcome.sent) {
      setState(
        () => _error = registrationCodeErrorMessage(context.l10n, outcome),
      );
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
    final l10n = context.l10n;
    return AuthScaffold(
      title: l10n.authGetSignUpCode,
      footer: [
        TextButton(
          onPressed: _loading ? null : () => _openRegisterPage(null),
          child: Text(l10n.authHaveCodeAlready),
        ),
      ],
      children: [
        Text(
          l10n.authCodeEmailExplainer,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        ZunoTextField(
          controller: _email,
          enabled: !_loading,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(
            labelText: l10n.authEmailLabel,
            border: const OutlineInputBorder(),
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
          child: Text(_loading ? l10n.authSendingCode : l10n.authSendCode),
        ),
      ],
    );
  }
}
