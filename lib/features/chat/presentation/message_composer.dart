import 'package:flutter/material.dart';

import '../../../core/format/human_units.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/zuno_motion.dart';
import '../../../core/ui/zuno_theme.dart';
import 'send_icon.dart';
import 'voice_recorder.dart';

class MessageComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool attaching;
  final VoiceRecorder recorder;

  const MessageComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.attaching,
    required this.recorder,
  });

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: recorder, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final isRecording = recorder.isRecording;
    final willCancel = recorder.willCancel;
    final handsFree = recorder.handsFree;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cancelColor = colors.error;
    final hintColor = colors.onSurfaceVariant;
    final l10n = context.l10n;
    final textStyle = theme.textTheme.bodyLarge!.copyWith(
      height: 1.3,
      letterSpacing: 0.2,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: isRecording
                  ? SizedBox(
                      height: 48,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.fiber_manual_record,
                              color: cancelColor,
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ValueListenableBuilder<Duration>(
                                valueListenable: recorder.elapsed,
                                builder: (context, duration, _) =>
                                    Text(formatDuration(duration)),
                              ),
                            ),
                            if (handsFree)
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: l10n.chatCancelRecording,
                                onPressed: recorder.cancel,
                              )
                            else
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedDefaultTextStyle(
                                    duration: ZunoDurations.fast,
                                    style: theme.textTheme.bodyMedium!.copyWith(
                                      color: willCancel
                                          ? cancelColor
                                          : hintColor,
                                      fontWeight: willCancel
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                    child: Text(
                                      willCancel
                                          ? l10n.chatReleaseToCancel
                                          : l10n.chatSlideToCancel,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.keyboard_arrow_up_outlined,
                                    color: willCancel ? cancelColor : hintColor,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: attaching
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.attach_file_outlined),
                          color: hintColor,
                          onPressed: attaching ? null : onAttach,
                        ),
                        Expanded(
                          child: ZunoTextField(
                            autofillHints: null,
                            controller: controller,
                            minLines: 1,
                            maxLines: 5,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            textCapitalization: TextCapitalization.sentences,
                            style: textStyle,
                            decoration: InputDecoration(
                              hintText: l10n.commonMessageHint,
                              hintStyle: textStyle.copyWith(color: hintColor),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final aboutToCancel = isRecording && willCancel;
              final Widget micIcon;
              if (!isRecording) {
                micIcon = const Icon(Icons.mic_none_outlined);
              } else if (handsFree) {
                micIcon = const SendIcon();
              } else {
                micIcon = const Icon(Icons.mic);
              }
              return AnimatedSwitcher(
                duration: ZunoDurations.fast,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.6, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: !isRecording && value.text.trim().isNotEmpty
                    ? _RoundIconButton(
                        key: const ValueKey('send'),
                        icon: const SendIcon(),
                        background: colors.primaryContainer,
                        iconColor: colors.onPrimaryContainer,
                        onPressed: onSend,
                      )
                    : Listener(
                        key: const ValueKey('mic'),
                        onPointerDown: recorder.pointerDown,
                        onPointerMove: recorder.pointerMove,
                        onPointerUp: recorder.pointerUp,
                        onPointerCancel: recorder.pointerCancel,
                        behavior: HitTestBehavior.opaque,
                        child: _RoundIconButton(
                          icon: micIcon,
                          background: aboutToCancel
                              ? cancelColor
                              : colors.primaryContainer,
                          iconColor: aboutToCancel
                              ? colors.onError
                              : colors.onPrimaryContainer,
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final Widget icon;
  final Color background;
  final Color iconColor;
  final VoidCallback? onPressed;

  const _RoundIconButton({
    super.key,
    required this.icon,
    required this.background,
    required this.iconColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: IconTheme.merge(
            data: IconThemeData(color: iconColor),
            child: icon,
          ),
        ),
      ),
    );
  }
}

class ComposeBar extends StatelessWidget {
  final String title;
  final String snippet;
  final VoidCallback onCancel;

  const ComposeBar({
    super.key,
    required this.title,
    required this.snippet,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(ZunoRadius.medium),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: ColoredBox(
                color: colors.primary,
                child: const SizedBox(width: 3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 13, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium!.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            snippet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: context.l10n.commonCancel,
                    onPressed: onCancel,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
