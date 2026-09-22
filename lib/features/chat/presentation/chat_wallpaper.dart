import 'package:flutter/material.dart';

const chatWallpaperAsset = 'assets/wallpaper/chat_tile.png';

const _chatWallpaperImage = AssetImage(chatWallpaperAsset);

Future<void> precacheChatWallpaper(BuildContext context) =>
    precacheImage(_chatWallpaperImage, context);

class ChatWallpaperBackground extends StatelessWidget {
  const ChatWallpaperBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: Image(
          image: _chatWallpaperImage,
          repeat: ImageRepeat.repeat,
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
          filterQuality: FilterQuality.low,
          color: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.05),
          colorBlendMode: BlendMode.srcIn,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
