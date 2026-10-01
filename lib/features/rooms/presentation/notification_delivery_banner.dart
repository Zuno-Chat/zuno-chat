import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/delivery_auto_fallback.dart';
import '../../../core/notifications/delivery_failure.dart';
import '../../../core/notifications/delivery_failure_provider.dart';
import '../../../core/security/security_emphasis.dart';
import '../../settings/presentation/delivery_failure_action.dart';

class NotificationDeliveryBanner extends ConsumerWidget {
  const NotificationDeliveryBanner({super.key});

  void _dismiss(WidgetRef ref, DeliveryFailure failure) {
    ref.read(dismissedDeliveryFailureProvider.notifier).dismiss(failure);
    if (failure.notice) {
      ref.read(autoSelectedDeliveryModeProvider.notifier).acknowledge();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = ref.watch(deliveryFailureProvider);
    final dismissed = ref.watch(dismissedDeliveryFailureProvider);
    if (failure == null || deliveryFailureIsDismissed(failure, dismissed)) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    final background = failure.notice
        ? colors.secondaryContainer
        : colors.errorContainer;
    final foreground = failure.notice
        ? colors.onSecondaryContainer
        : colors.onErrorContainer;

    return Material(
      key: const ValueKey('deliveryFailureBanner'),
      color: background,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!failure.notice) const AttentionStripe(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
                child: Row(
                  children: [
                    Icon(
                      failure.notice ? Icons.info_outline : attentionIcon,
                      color: foreground,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            failure.message,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton(
                              onPressed: () => runDeliveryFailureAction(
                                context,
                                ref,
                                failure,
                              ),
                              child: Text(
                                deliveryFailureActionLabel(failure.action),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Dismiss',
                      color: foreground,
                      onPressed: () => _dismiss(ref, failure),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
