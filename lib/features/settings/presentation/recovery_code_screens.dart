import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/files/picked_file.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/security/recovery_code.dart';
import '../../../core/security/recovery_code_file.dart';
import '../../../core/security/secret_text.dart';
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
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.settingsRecoveryPrepareFailed),
        ),
      ),
      data: (list) {
        final code = _code ??= generateRecoveryCode(list);
        switch (_step) {
          case _Step.reveal:
            return _RevealScreen(
              code: code,
              capabilities: ref.watch(platformCapabilitiesProvider),
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
  final PlatformCapabilities capabilities;
  final VoidCallback onContinue;
  const _RevealScreen({
    required this.code,
    required this.capabilities,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final words = code.split(' ');
    return StepLayout(
      hero: const StepHero(icon: Icons.vpn_key_outlined, compact: true),
      title: l10n.settingsRecoveryRevealTitle(words.length),
      body: l10n.settingsRecoveryRevealBody,
      children: [
        _WordGrid(words: words),
        const SizedBox(height: 24),
        _WideButton(
          icon: Icons.save_outlined,
          label: l10n.settingsRecoverySaveAsFile,
          onPressed: () => _saveAsFile(context, code, capabilities),
        ),
        const SizedBox(height: 8),
        _WideButton(
          icon: Icons.copy_outlined,
          label: l10n.commonCopy,
          onPressed: () {
            SensitiveClipboard.instance.copy(code);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  capabilities.sensitiveClipboard
                      ? l10n.settingsCopiedSensitive
                      : l10n.settingsRecoveryCopiedStays,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onContinue, child: Text(l10n.commonContinue)),
      ],
    );
  }
}

Future<void> _saveAsFile(
  BuildContext context,
  String code,
  PlatformCapabilities capabilities,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    if (!await saveRecoveryCodeFile(l10n, code, capabilities: capabilities)) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.settingsRecoverySaved)));
  } catch (e, s) {
    reportCaught('save recovery code file', e, s);
    messenger.showSnackBar(SnackBar(content: Text(l10n.commonSaveFailed)));
  }
}

class _WideButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const _WideButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
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
              context.l10n.settingsRecoveryWordNumber(index + 1),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SecretText(
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
        setState(() => _error = context.l10n.settingsRecoveryMismatch);
        return;
      }
    }
    setState(() => _error = null);
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final positions = widget.indices
        .map((i) => l10n.securityOrdinal('${i + 1}'))
        .toList();
    return StepLayout(
      hero: const StepHero(icon: Icons.checklist_outlined, compact: true),
      title: l10n.settingsRecoveryConfirmTitle,
      body: l10n.settingsRecoveryConfirmBody(positions[0], positions[1]),
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
              : Text(l10n.commonDone),
        ),
        TextButton(
          onPressed: widget.busy ? null : widget.onBack,
          child: Text(l10n.settingsRecoveryShowAgain),
        ),
      ],
      children: [
        for (var i = 0; i < widget.indices.length; i++) ...[
          SecretTextField(
            controller: _controllers[i],
            autofocus: i == 0,
            decoration: InputDecoration(
              labelText: l10n.settingsRecoveryWordLabel(positions[i]),
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
  bool _opening = false;
  bool _copying = false;

  Future<void> _openSavedFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _opening = true);
    try {
      final file = await trackPickerCopy(
        (onFileLoading) => FilePicker.pickFile(
          dialogTitle: l10n.settingsRecoveryOpenDialogTitle,
          onFileLoading: onFileLoading,
        ),
        onCopying: (copying) {
          if (mounted) setState(() => _copying = copying);
        },
      );
      if (file == null) return;
      final code = await readPickedRecoveryCodeFile(file);
      if (!mounted) return;
      if (code == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsRecoveryNotACode)),
        );
        return;
      }
      widget.controller.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
    } catch (e, s) {
      reportCaught('open recovery code file', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsRecoveryOpenFailed)),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wordlist = maybeWordlist(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: SecretTextField(
            autofillHints: const [AutofillHints.password],
            controller: widget.controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: context.l10n.settingsRecoveryCodeLabel,
              hintText: context.l10n.settingsRecoveryCodeHint(
                recoveryCodeWordCount,
              ),
              border: const OutlineInputBorder(),
              errorText: widget.error,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => widget.busy ? null : widget.onSubmit(),
          ),
        ),
        if (wordlist != null) _hint(context, wordlist),
        const SizedBox(height: 16),
        _WideButton(
          icon: Icons.file_open_outlined,
          label: context.l10n.settingsRecoveryOpenSavedFile,
          onPressed: widget.busy || _opening ? null : _openSavedFile,
          busy: _copying,
        ),
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
    final l10n = context.l10n;

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
            ? l10n.settingsRecoveryUnknownWord(typed)
            : l10n.settingsRecoveryUnknownWordSuggestions(
                typed,
                suggestions.join(', '),
              ),
        colors.error,
      );
    }
    if (words.length < recoveryCodeWordCount) {
      final missing = recoveryCodeWordCount - words.length;
      return line(
        l10n.settingsRecoveryWordsToGo(missing),
        colors.onSurfaceVariant,
      );
    }
    if (words.length > recoveryCodeWordCount) {
      return line(
        l10n.settingsRecoveryTooManyWords(words.length, recoveryCodeWordCount),
        colors.error,
      );
    }
    return line(l10n.settingsRecoveryLooksRight, colors.onSurfaceVariant);
  }
}
