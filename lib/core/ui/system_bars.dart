import 'package:flutter/services.dart';

Future<void> hideSystemBars() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

Future<void> showSystemBars() async {
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}
