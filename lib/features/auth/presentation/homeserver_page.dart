import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/auth/auth_error_message.dart';
import '../../../core/matrix/auth/homeserver.dart';
import '../../../core/matrix/auth/homeserver_input.dart';
import '../../../core/matrix/auth/server_choice.dart';
import '../../../core/matrix/client/matrix_client_provider.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/inline_feedback.dart';
import '../../../core/ui/keyboard.dart';
import '../../../core/ui/retry_wait.dart';
import 'auth_scaffold.dart';

class HomeserverPage extends ConsumerStatefulWidget {
  const HomeserverPage({super.key});

  @override
  ConsumerState<HomeserverPage> createState() => _HomeserverPageState();
}

class _HomeserverPageState extends ConsumerState<HomeserverPage>
    with RetryWait<HomeserverPage> {
  late final TextEditingController _homeserver;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(homeserverProvider).value?.homeserver;
    final text = current == null ? '' : homeserverInputText(current);
    _homeserver = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  @override
  void dispose() {
    _homeserver.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (waitingToRetry) return;
    closeKeyboard();
    final parsed = parseHomeserverInput(context.l10n, _homeserver.text);
    final shapeError = parsed.error;
    if (shapeError != null) {
      setState(() => _error = shapeError);
      return;
    }
    final homeserver = parsed.uri!;

    setState(() {
      _loading = true;
      _error = null;
    });

    final route = ModalRoute.of(context);
    try {
      final choice = await checkServer(
        ref.read(matrixClientProvider),
        homeserver,
      );
      if (!mounted || !(route?.isActive ?? false)) return;
      ref.read(homeserverProvider.notifier).adopt(choice);
      Navigator.of(context).pop();
    } catch (e, s) {
      if (homeserverProblem(e).reported) reportCaught('use homeserver', e, s);
      if (!mounted) return;
      setState(() => _error = homeserverErrorMessage(context.l10n, e));
      holdRetriesFor(retryWaitFor(e), whenOver: () => _error = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthScaffold(
      title: l10n.authConnectToServer,
      children: [
        ZunoTextField(
          autofillHints: null,
          controller: _homeserver,
          enabled: !_loading,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onSubmitted: (_) => _continue(),
          decoration: InputDecoration(
            hintText: l10n.authHomeserverHint,
            helperText: l10n.authServerHelper,
          ),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 16),
          InlineError(error),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loading || waitingToRetry ? null : _continue,
          child: Text(_loading ? l10n.authConnecting : l10n.commonContinue),
        ),
      ],
    );
  }
}
