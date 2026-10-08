import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/call_picture_in_picture.dart';
import '../../../core/calls/models/call_surface.dart';
import '../../../core/navigation/global_navigator.dart';
import '../../../core/ui/keep_clear.dart';
import '../../../core/ui/top_banner_frame.dart';
import '../../../core/ui/zuno_theme.dart';
import 'call_bar.dart';
import 'call_page.dart';
import 'call_window.dart';
import 'participant_tile.dart';

class CallLayer extends ConsumerWidget {
  final List<Widget?> banners;
  final Widget child;

  const CallLayer({required this.child, this.banners = const [], super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(activeCallControllerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([?call]),
      builder: (context, _) {
        final surface = call?.surface ?? CallSurface.none;
        final pictureInPicture = surface == CallSurface.pictureInPicture;
        return Stack(
          children: [
            Positioned.fill(
              key: const ValueKey('app'),
              child: Offstage(
                offstage: pictureInPicture,
                child: TickerMode(
                  enabled: !pictureInPicture,
                  child: TopBannerFrame(
                    banners: [
                      surface == CallSurface.bar
                          ? CallBar(call: call!, onTap: () => _open(call))
                          : null,
                      ...banners,
                    ],
                    child: _CallWindowHost(
                      call: surface == CallSurface.window ? call : null,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
            if (pictureInPicture)
              Positioned.fill(
                key: const ValueKey('picture-in-picture'),
                child: _PictureInPictureTile(call: call!),
              ),
          ],
        );
      },
    );
  }
}

void _open(ActiveCallController call) {
  final navigator = globalNavigatorKey.currentState;
  if (navigator != null) showCallScreen(navigator, call);
}

class _CallWindowHost extends StatelessWidget {
  final ActiveCallController? call;
  final Widget child;

  const _CallWindowHost({required this.call, required this.child});

  @override
  Widget build(BuildContext context) {
    final call = this.call;
    final remote = call?.videoRemote;
    return KeepClearScope(
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(child: child),
            if (call != null && remote != null)
              CallWindow(
                key: ObjectKey(call),
                call: call,
                remote: remote,
                area: constraints.biggest,
                onTap: () => _open(call),
              ),
          ],
        ),
      ),
    );
  }
}

class _PictureInPictureTile extends StatelessWidget {
  final ActiveCallController call;

  const _PictureInPictureTile({required this.call});

  @override
  Widget build(BuildContext context) {
    final remote =
        pictureInPictureRemote(call.participants) ?? call.remotes.firstOrNull;
    return Theme(
      data: zunoDarkTheme,
      child: Material(
        color: Colors.black,
        child: remote == null
            ? const SizedBox.expand()
            : ParticipantTile(
                participant: remote,
                renderer: call.rendererFor(remote.id),
                user: call.userFor(remote),
                encrypting: call.encrypting(remote),
                borderRadius: 0,
              ),
      ),
    );
  }
}
