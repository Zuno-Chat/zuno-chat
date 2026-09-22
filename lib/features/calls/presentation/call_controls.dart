import 'package:flutter/material.dart';

import '../../../core/calls/models/call_kind.dart';
import '../../../core/ui/zuno_colors.dart';

class CallControls extends StatelessWidget {
  final CallKind kind;
  final bool micMuted;
  final bool cameraOn;
  final bool speakerOn;
  final bool enabled;
  final bool overVideo;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onHangUp;

  const CallControls({
    super.key,
    required this.kind,
    required this.micMuted,
    required this.cameraOn,
    required this.speakerOn,
    required this.enabled,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onToggleSpeaker,
    required this.onHangUp,
    this.overVideo = false,
  });

  String get _cameraTooltip {
    if (kind == CallKind.voice) return 'Switch to video call';
    return cameraOn ? 'Turn camera off' : 'Turn camera on';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: overVideo ? Colors.black54 : colors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(36),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            _ControlButton(
              icon: micMuted ? Icons.mic_off_outlined : Icons.mic_outlined,
              tooltip: micMuted ? 'Unmute' : 'Mute',
              on: micMuted,
              overVideo: overVideo,
              onPressed: enabled ? onToggleMute : null,
            ),
            _ControlButton(
              icon: cameraOn
                  ? Icons.videocam_outlined
                  : Icons.videocam_off_outlined,
              tooltip: _cameraTooltip,
              on: cameraOn,
              overVideo: overVideo,
              onPressed: enabled ? onToggleCamera : null,
            ),
            if (cameraOn)
              _ControlButton(
                icon: Icons.cameraswitch_outlined,
                tooltip: 'Switch camera',
                on: false,
                overVideo: overVideo,
                onPressed: enabled ? onSwitchCamera : null,
              ),
            _ControlButton(
              icon: speakerOn
                  ? Icons.volume_up_outlined
                  : Icons.hearing_outlined,
              tooltip: speakerOn ? 'Turn speaker off' : 'Turn speaker on',
              on: speakerOn,
              overVideo: overVideo,
              onPressed: enabled ? onToggleSpeaker : null,
            ),
            _ControlButton(
              icon: Icons.call_end,
              tooltip: 'End call',
              fill: callEndColor,
              ink: onCallActionColor,
              on: false,
              overVideo: overVideo,
              holdShowsTooltip: false,
              onPressed: onHangUp,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool on;
  final bool overVideo;
  final Color? fill;
  final Color? ink;
  final bool holdShowsTooltip;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.on,
    required this.overVideo,
    required this.onPressed,
    this.fill,
    this.ink,
    this.holdShowsTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final quiet = overVideo ? Colors.white24 : colors.surfaceContainerHighest;
    final background = fill ?? (on ? colors.onSurface : quiet);
    final foreground = ink ?? (on ? colors.surface : colors.onSurface);
    final disabled = onPressed == null;
    return Tooltip(
      message: tooltip,
      triggerMode: holdShowsTooltip
          ? TooltipTriggerMode.longPress
          : TooltipTriggerMode.manual,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        enabled: !disabled,
        tooltip: tooltip,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(
                icon,
                color: disabled
                    ? foreground.withValues(alpha: 0.38)
                    : foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
