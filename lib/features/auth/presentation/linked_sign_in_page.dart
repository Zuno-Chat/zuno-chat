import 'dart:convert' show utf8;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/homeserver.dart';
import '../../../core/matrix/linked_sign_in.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/session_display_name.dart';
import '../../../core/ui/keyboard.dart';
import '../../verification/presentation/qr_scanner_page.dart';
import 'auth_scaffold.dart';
import 'retry_wait.dart';

typedef CodeScanner = Future<Uint8List?> Function(BuildContext context);

Future<Uint8List?> scanCodeWithCamera(BuildContext context) =>
    Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => const QrScannerPage(title: 'Scan the sign-in code'),
      ),
    );

class LinkedSignInPage extends ConsumerStatefulWidget {
  final CodeScanner scan;

  const LinkedSignInPage({this.scan = scanCodeWithCamera, super.key});

  @override
  ConsumerState<LinkedSignInPage> createState() => _LinkedSignInPageState();
}

class _LinkedSignInPageState extends ConsumerState<LinkedSignInPage>
    with RetryWait<LinkedSignInPage> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _busy => _loading || waitingToRetry;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_busy) return;
    closeKeyboard();
    final bytes = await widget.scan(context);
    if (!mounted || bytes == null) return;
    final code = LinkedSignInCode.decode(
      utf8.decode(bytes, allowMalformed: true),
    );
    if (code == null) {
      setState(() => _error = notASignInCodeMessage);
      return;
    }
    await _useCode(code);
  }

  Future<void> _useCode(LinkedSignInCode code) async {
    if (_busy) return;
    final Uri chosen;
    try {
      chosen = await ref.read(homeserverProvider.future);
    } catch (e) {
      if (mounted) setState(() => _error = linkedSignInErrorMessage(e));
      return;
    }
    if (!mounted) return;
    if (!code.isForServer(chosen.host)) {
      setState(() => _error = codeForAnotherServerMessage(code.server));
      return;
    }
    await _signIn(code.token);
  }

  Future<void> _submitTyped() async {
    if (_busy) return;
    closeKeyboard();
    final token = typedSignInCode(_code.text);
    if (token.isEmpty) {
      setState(() => _error = 'Enter the code');
      return;
    }
    await _signIn(token);
  }

  Future<void> _signIn(String token) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = ref.read(matrixClientProvider);
    try {
      await signInWithLinkedCode(
        client,
        token: token,
        deviceDisplayName: sessionDisplayName(Platform.operatingSystem),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = linkedSignInErrorMessage(e));
      holdRetriesFor(e, whenOver: () => _error = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AuthScaffold(
      title: 'Sign in with your other device',
      children: [
        const Text(
          'On a device that is already signed in, open Settings, then Your '
          'devices, then Sign in on another device.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _scan,
          child: const Text('Scan code'),
        ),
        const SizedBox(height: 24),
        Text(
          'Or type the code it shows',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          enabled: !_loading,
          autofillHints: null,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitTyped(),
          decoration: const InputDecoration(
            labelText: 'Code',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _busy ? null : _submitTyped,
          child: Text(_loading ? 'Signing in…' : 'Sign in with the code'),
        ),
      ],
    );
  }
}
