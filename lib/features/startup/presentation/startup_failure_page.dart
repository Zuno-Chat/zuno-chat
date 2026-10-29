import 'package:flutter/material.dart';

import '../../../core/brand.dart';
import '../../../core/l10n/app_locale.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/client_startup.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/zuno_theme.dart';

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.onChoice});

  final ValueChanged<StartupChoice> onChoice;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: AppLocale.instance,
      builder: (context, locale, _) => MaterialApp(
        title: zunoName,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: zunoLightTheme,
        darkTheme: zunoDarkTheme,
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: StartupFailurePage(onChoice: onChoice),
      ),
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
    final l10n = context.l10n;
    final confirmed = await confirm(
      context,
      title: l10n.startupStartOverTitle,
      body: l10n.startupStartOverBody,
      confirmLabel: l10n.startupDeleteAndStartOver,
      tone: ConfirmTone.destructive,
    );
    if (confirmed) _choose(StartupChoice.startOver);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
                  l10n.startupFailedTitle,
                  style: textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.startupFailedBody,
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _chosen
                      ? null
                      : () => _choose(StartupChoice.tryAgain),
                  child: Text(l10n.commonTryAgain),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _chosen ? null : _confirmStartOver,
                  child: Text(l10n.startupStartOver),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
