import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/homeserver.dart';
import '../../../core/security/device_safety.dart';
import '../../../core/ui/zuno_splash.dart';
import 'auth_scaffold.dart';
import 'device_warning_page.dart';
import 'homeserver_page.dart';
import 'login_page.dart';

class SignedOutEntry extends ConsumerWidget {
  const SignedOutEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeserver = ref.watch(homeserverProvider);
    if (!ref.watch(deviceWarningAcknowledgedProvider)) {
      final risks = ref.watch(deviceRisksProvider);
      if (risks.isLoading) return const ZunoSplash();
      final found = risks.value ?? const <DeviceRisk>{};
      if (found.isNotEmpty) {
        return DeviceWarningPage(
          risks: found,
          onContinue: ref
              .read(deviceWarningAcknowledgedProvider.notifier)
              .acknowledge,
        );
      }
    }
    return homeserver.when(
      data: (_) => const LoginPage(),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => _Unreachable(
        message: homeserverErrorMessage(error),
        onRetry: () => ref.invalidate(homeserverProvider),
        onChangeServer: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const HomeserverPage())),
      ),
    );
  }
}

class _Unreachable extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onChangeServer;

  const _Unreachable({
    required this.message,
    required this.onRetry,
    required this.onChangeServer,
  });

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Try again')),
        TextButton(
          onPressed: onChangeServer,
          child: const Text('Use another server'),
        ),
      ],
    );
  }
}
