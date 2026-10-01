import 'package:flutter/material.dart';

import '../../../core/matrix/client_startup.dart';
import '../../../core/ui/zuno_theme.dart';

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.onChoice});

  final ValueChanged<StartupChoice> onChoice;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zuno',
      theme: zunoLightTheme,
      darkTheme: zunoDarkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: StartupFailurePage(onChoice: onChoice),
    );
  }
}

class StartupFailurePage extends StatefulWidget {
  const StartupFailurePage({super.key, required this.onChoice});

  final ValueChanged<StartupChoice> onChoice;

  @override
  State<StartupFailurePage> createState() => _StartupFailurePageState();
}

class _StartupFailurePageState extends State<StartupFailurePage> {
  bool _chosen = false;

  void _choose(StartupChoice choice) {
    if (_chosen) return;
    setState(() => _chosen = true);
    widget.onChoice(choice);
  }

  Future<void> _confirmStartOver() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start over on this device?'),
        content: const Text(
          'This deletes the chats and encryption keys Zuno stored on this '
          'device. You then sign in again, and your message history comes '
          'back only with your recovery code or another signed-in device. '
          'Nobody can undo this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete and start over'),
          ),
        ],
      ),
    );
    if (confirmed == true) _choose(StartupChoice.startOver);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Zuno could not start',
                  style: textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'The chats and keys stored on this device could not be '
                  'opened. Nothing has been deleted. Try again, and if this '
                  'keeps happening, restart your device or free up some '
                  'storage.',
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _chosen
                      ? null
                      : () => _choose(StartupChoice.tryAgain),
                  child: const Text('Try again'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _chosen ? null : _confirmStartOver,
                  child: const Text('Start over on this device'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
