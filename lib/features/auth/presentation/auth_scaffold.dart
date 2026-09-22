import 'package:flutter/material.dart';

import '../../../core/ui/zuno_theme.dart';
import 'auth_logo.dart';

const authCardKey = ValueKey('auth-card');

class AuthScaffold extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final List<Widget> footer;

  const AuthScaffold({
    super.key,
    this.title,
    required this.children,
    this.footer = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = this.title;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthLogo(),
                  Material(
                    key: authCardKey,
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(ZunoRadius.large),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (title != null) ...[
                            Text(title, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 12),
                          ],
                          ...children,
                        ],
                      ),
                    ),
                  ),
                  if (footer.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...footer,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
