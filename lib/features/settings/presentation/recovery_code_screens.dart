import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/security/recovery_code.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/sensitive_clipboard.dart';
import '../../../core/ui/step_hero.dart';
import '../../../core/ui/step_layout.dart';

class RecoveryCodeCreateFlow extends ConsumerStatefulWidget {
  final bool busy;
  final ValueChanged<String> onComplete;

  const RecoveryCodeCreateFlow({
    required this.busy,
    required this.onComplete,
    super.key,
  });

  @override
  ConsumerState<RecoveryCodeCreateFlow> createState() =>
      _RecoveryCodeCreateFlowState();
}

enum _Step { reveal, confirm }

class _RecoveryCodeCreateFlowState
    extends ConsumerState<RecoveryCodeCreateFlow> {
  _Step _step = _Step.reveal;
  String? _code;
  List<int>? _confirmIndices;

  @override
  Widget build(BuildContext context) {
    final wordlist = ref.watch(recoveryWordlistProvider);
    return wordlist.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Could not prepare a recovery code. Go back and try again.',
          ),
        ),
      ),
      data: (list) {
        final code = _code ??= generateRecoveryCode(list);
        switch (_step) {
          case _Step.reveal:
            return _RevealScreen(
              code: code,
              onContinue: () => setState(() {
                _confirmIndices = recoveryConfirmationIndices();
                _step = _Step.confirm;
              }),
            );
          case _Step.confirm:
            return _ConfirmScreen(
              code: code,
              indices: _confirmIndices!,
              busy: widget.busy,
              onBack: () => setState(() => _step = _Step.reveal),
              onConfirmed: () => widget.onComplete(code),
            );
        }
      },
    );
  }
}

class _RevealScreen extends StatelessWidget {
  final String code;
  final VoidCallback onContinue;
  const _RevealScreen({required this.code, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final words = code.split(' ');
    return StepLayout(
      hero: const StepHero(icon: Icons.vpn_key_outlined, compact: true),
      title: 'These ${words.length} words are your recovery code',
      body:
          'If you lose this device and every other signed-in device, this code '
          'is the only way back to your messages. Nobody can restore them for '
          'you. Write it down, or save it below.',
      children: [
        _WordGrid(words: words),
        const SizedBox(height: 24),
        _SaveButton(
          icon: Icons.password_outlined,
          label: 'Save to password manager',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => _PasswordManagerSaveDialog(code: code),
          ),
        ),
        const SizedBox(height: 8),
        _SaveButton(
          icon: Icons.save_outlined,
          label: 'Save as a file',
          onPressed: () => _saveAsFile(context, code),
        ),
        const SizedBox(height: 8),
        _SaveButton(
          icon: Icons.copy_outlined,
          label: 'Copy',
          onPressed: () {
            SensitiveClipboard.instance.copy(code);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Copied. Clears from the clipboard in 90 seconds.',
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onContinue, child: const Text('Continue')),
      ],
    );
  }
}

class _PasswordManagerSaveDialog extends StatefulWidget {
  final String code;
  const _PasswordManagerSaveDialog({required this.code});

  @override
  State<_PasswordManagerSaveDialog> createState() =>
      _PasswordManagerSaveDialogState();
}

class _PasswordManagerSaveDialogState
    extends State<_PasswordManagerSaveDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.code,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save to your password manager'),
      content: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your password manager should offer to save this. Give it a name '
              'you will recognize, such as "Zuno recovery code".',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              readOnly: true,
              maxLines: 2,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Recovery code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            TextInput.finishAutofillContext();
            Navigator.of(context).pop();
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}

Future<void> _saveAsFile(BuildContext context, String code) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save your recovery code',
      fileName: 'zuno-recovery-code.txt',
      mimeType: 'text/plain',
      bytes: Uint8List.fromList(utf8.encode('$code\n')),
    );
    if (uri == null) return;
    messenger.showSnackBar(const SnackBar(content: Text('Saved')));
  } catch (e) {
    logCaught('save recovery code file', e);
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not save. Try again.')),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SaveButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Align(alignment: Alignment.centerLeft, child: Text(label)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        alignment: Alignment.centerLeft,
      ),
    );
  }
}

class _WordGrid extends StatelessWidget {
  final List<String> words;
  const _WordGrid({required this.words});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = (words.length + 1) ~/ 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns =
              constraints.maxWidth >=
              260 * MediaQuery.textScalerOf(context).scale(1);
          if (!twoColumns) {
            return Column(
              children: [
                for (var i = 0; i < words.length; i++)
                  _WordRow(index: i, word: words[i]),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < 2; column++) ...[
                if (column > 0) const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      for (
                        var i = column * rows;
                        i < (column + 1) * rows && i < words.length;
                        i++
                      )
                        _WordRow(index: i, word: words[i]),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WordRow extends StatelessWidget {
  final int index;
  final String word;
  const _WordRow({required this.index, required this.word});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              word,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontFamily: 'monospace', letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmScreen extends StatefulWidget {
  final String code;
  final List<int> indices;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onConfirmed;

  const _ConfirmScreen({
    required this.code,
    required this.indices,
    required this.busy,
    required this.onBack,
    required this.onConfirmed,
  });

  @override
  State<_ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<_ConfirmScreen> {
  late final List<TextEditingController> _controllers = [
    for (final _ in widget.indices) TextEditingController(),
  ];
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final words = widget.code.split(' ');
    for (var i = 0; i < widget.indices.length; i++) {
      final expected = words[widget.indices[i]];
      final typed = normalizeRecoveryPhrase(_controllers[i].text);
      if (typed != expected) {
        setState(() => _error = 'That does not match. Check your saved copy.');
        return;
      }
    }
    setState(() => _error = null);
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final positions = widget.indices.map((i) => ordinal(i + 1)).toList();
    return StepLayout(
      hero: const StepHero(icon: Icons.checklist_outlined, compact: true),
      title: 'Check your saved copy',
      body: 'Type the ${positions.join(' and ')} words from your saved copy.',
      actions: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: widget.busy ? null : _submit,
          child: widget.busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Done'),
        ),
        TextButton(
          onPressed: widget.busy ? null : widget.onBack,
          child: const Text('Show the code again'),
        ),
      ],
      children: [
        for (var i = 0; i < widget.indices.length; i++) ...[
          TextField(
            autofillHints: null,
            controller: _controllers[i],
            autofocus: i == 0,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              labelText: '${positions[i]} word',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class RecoveryCodeEntryField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final String? error;
  final bool busy;
  final VoidCallback onSubmit;

  const RecoveryCodeEntryField({
    required this.controller,
    required this.error,
    required this.busy,
    required this.onSubmit,
    super.key,
  });

  @override
  ConsumerState<RecoveryCodeEntryField> createState() =>
      _RecoveryCodeEntryFieldState();
}

class _RecoveryCodeEntryFieldState
    extends ConsumerState<RecoveryCodeEntryField> {
  @override
  Widget build(BuildContext context) {
    final wordlist = maybeWordlist(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: TextField(
            autofillHints: const [AutofillHints.password],
            controller: widget.controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: 'Recovery code',
              hintText: '$recoveryCodeWordCount words, separated by spaces',
              border: const OutlineInputBorder(),
              errorText: widget.error,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => widget.busy ? null : widget.onSubmit(),
          ),
        ),
        if (wordlist != null) _hint(context, wordlist),
      ],
    );
  }

  Widget _hint(BuildContext context, RecoveryWordlist wordlist) {
    final text = widget.controller.text;
    if (text.trim().isEmpty) return const SizedBox(height: 8);
    if (looksLikeSecurityKey(text)) return const SizedBox(height: 8);

    final check = checkRecoveryCode(text, wordlist);
    final words = check.normalized.isEmpty
        ? <String>[]
        : check.normalized.split(' ');
    final colors = Theme.of(context).colorScheme;

    Widget line(String message, Color color) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );

    if (check.unknownWordIndices.isNotEmpty) {
      final typed = words[check.unknownWordIndices.first];
      final suggestions = wordlist.suggestionsFor(typed);
      return line(
        suggestions.isEmpty
            ? '"$typed" is not one of the words.'
            : '"$typed" is not one of the words. Did you mean '
                  '${suggestions.join(', ')}?',
        colors.error,
      );
    }
    if (words.length < recoveryCodeWordCount) {
      final missing = recoveryCodeWordCount - words.length;
      return line(
        '$missing more word${missing == 1 ? '' : 's'} to go.',
        colors.onSurfaceVariant,
      );
    }
    if (words.length > recoveryCodeWordCount) {
      return line(
        'That is ${words.length} words. A code has $recoveryCodeWordCount.',
        colors.error,
      );
    }
    return line('Looks right.', colors.onSurfaceVariant);
  }
}
