import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/homeserver.dart';
import '../../../core/matrix/homeserver_input.dart';
import '../../../core/ui/keyboard.dart';
import 'auth_scaffold.dart';

class HomeserverPage extends ConsumerStatefulWidget {
  const HomeserverPage({super.key});

  @override
  ConsumerState<HomeserverPage> createState() => _HomeserverPageState();
}

class _HomeserverPageState extends ConsumerState<HomeserverPage> {
  late final TextEditingController _homeserver;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(homeserverProvider).value;
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
    closeKeyboard();
    final parsed = parseHomeserverInput(_homeserver.text);
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

    try {
      await ref.read(homeserverProvider.notifier).use(homeserver);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = homeserverErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Connect to a server',
      children: [
        TextField(
          autofillHints: null,
          controller: _homeserver,
          enabled: !_loading,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onSubmitted: (_) => _continue(),
          decoration: const InputDecoration(
            labelText: 'Server',
            hintText: 'chat.example.org',
            helperText: 'A hostname or a full https:// address',
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
          onPressed: _loading ? null : _continue,
          child: Text(_loading ? 'Connecting…' : 'Continue'),
        ),
      ],
    );
  }
}
