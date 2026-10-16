import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/push/delivery/delivery_auto_fallback.dart';
import '../../../core/push/delivery/delivery_failure.dart';
import '../../../core/push/delivery/delivery_failure_provider.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/ui/alert_banner.dart';
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
    if (failure == null || failure == dismissed) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    return AlertBanner(
      key: const ValueKey('deliveryFailureBanner'),
      tone: failure.notice ? AlertBannerTone.notice : AlertBannerTone.attention,
      icon: failure.notice ? Icons.info_outline : attentionIcon,
      title: failure.message(l10n),
      actionLabel: deliveryFailureActionLabel(l10n, failure.action),
      onAction: () => runDeliveryFailureAction(context, ref, failure),
      onDismiss: () => _dismiss(ref, failure),
    );
  }
}
