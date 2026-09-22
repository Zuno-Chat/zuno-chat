import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/zuno_motion.dart';
import '../../../core/ui/zuno_theme.dart';
import '../data/message_kinds.dart';
import 'send_icon.dart';

class MessageComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool incognitoKeyboard;
  final bool isRecording;
  final ValueListenable<Duration> recordingDuration;
  final bool recordingWillCancel;
  final bool tapToggleRecording;
  final void Function(PointerDownEvent) onMicPointerDown;
  final void Function(PointerMoveEvent) onMicPointerMove;
  final void Function(PointerUpEvent) onMicPointerUp;
  final void Function(PointerCancelEvent) onMicPointerCancel;
  final VoidCallback onCancelRecording;

  const MessageComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.incognitoKeyboard,
    required this.isRecording,
    required this.recordingDuration,
    required this.recordingWillCancel,
    required this.tapToggleRecording,
    required this.onMicPointerDown,
    required this.onMicPointerMove,
    required this.onMicPointerUp,
    required this.onMicPointerCancel,
    required this.onCancelRecording,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cancelColor = colors.error;
    final hintColor = colors.onSurfaceVariant;
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
                                valueListenable: recordingDuration,
                                builder: (context, duration, _) =>
                                    Text(formatDuration(duration)),
                              ),
                            ),
                            if (tapToggleRecording)
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Cancel recording',
                                onPressed: onCancelRecording,
                              )
                            else
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedDefaultTextStyle(
                                    duration: ZunoDurations.fast,
                                    style: theme.textTheme.bodyMedium!.copyWith(
                                      color: recordingWillCancel
                                          ? cancelColor
                                          : hintColor,
                                      fontWeight: recordingWillCancel
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                    child: Text(
                                      recordingWillCancel
                                          ? 'Release to cancel'
                                          : 'Slide up to cancel',
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.keyboard_arrow_up_outlined,
                                    color: recordingWillCancel
                                        ? cancelColor
                                        : hintColor,
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
                          icon: const Icon(Icons.attach_file_outlined),
                          color: hintColor,
                          onPressed: onAttach,
                        ),
                        Expanded(
                          child: TextField(
                            autofillHints: null,
                            controller: controller,
                            minLines: 1,
                            maxLines: 5,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            textCapitalization: TextCapitalization.sentences,
                            enableIMEPersonalizedLearning: !incognitoKeyboard,
                            style: textStyle,
                            decoration: InputDecoration(
                              hintText: 'Message',
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
              final aboutToCancel = isRecording && recordingWillCancel;
              final Widget micIcon;
              if (!isRecording) {
                micIcon = const Icon(Icons.mic_none_outlined);
              } else if (tapToggleRecording) {
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
                        onPointerDown: onMicPointerDown,
                        onPointerMove: onMicPointerMove,
                        onPointerUp: onMicPointerUp,
                        onPointerCancel: onMicPointerCancel,
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
                    tooltip: 'Cancel',
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
