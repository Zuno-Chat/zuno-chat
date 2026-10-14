import 'dart:convert' show utf8;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
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
        builder: (routeContext) => QrScannerPage(
          title: routeContext.l10n.authLinkedScanTitle,
          withoutCamera: routeContext.l10n.authLinkedScanWithoutCamera,
        ),
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
      setState(() => _error = context.l10n.matrixLinkedSignInNotACode);
      return;
    }
    await _signIn(server: code.server, token: code.token);
  }

  Future<void> _submitTyped() async {
    if (_busy) return;
    closeKeyboard();
    final code = parseTypedSignInCode(_code.text);
    if (code == null) {
      setState(() => _error = context.l10n.authEnterCode);
      return;
    }
    await _signIn(server: code.server, token: code.token);
  }

  Future<void> _signIn({required String? server, required String token}) async {
    if (_busy) return;
    final Uri chosen;
    try {
      chosen = await ref.read(homeserverProvider.future);
    } catch (e) {
      if (mounted) {
        setState(() => _error = linkedSignInErrorMessage(context.l10n, e));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = ref.read(matrixClientProvider);
    try {
      await ref
          .read(signInInFlightProvider.notifier)
          .during(
            () => signInWithLinkedCode(
              client,
              server: server,
              token: token,
              chosenServer: chosen,
              deviceDisplayName: sessionDisplayName(Platform.operatingSystem),
            ),
          );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e, s) {
      if (!isLinkedSignInRefusal(e)) reportCaught('linked sign in', e, s);
      if (!mounted) return;
      setState(() => _error = linkedSignInErrorMessage(context.l10n, e));
      holdRetriesFor(e, whenOver: () => _error = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return PopScope(
      canPop: !_loading,
      child: AuthScaffold(
        title: l10n.authSignInWithOtherDevice,
        children: [
          Text(l10n.authLinkedInstructions),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _scan,
            child: Text(l10n.authScanCode),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.authOrTypeCode,
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
            minLines: 1,
            maxLines: 2,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitTyped(),
            decoration: InputDecoration(
              labelText: l10n.authCodeLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _busy ? null : _submitTyped,
            child: Text(
              _loading ? l10n.authSigningIn : l10n.authSignInWithCode,
            ),
          ),
        ],
      ),
    );
  }
}
