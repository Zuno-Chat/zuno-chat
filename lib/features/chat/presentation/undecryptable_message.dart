import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/undecryptable_reason.dart';
import '../../../core/security/security_providers.dart';
import '../../verification/presentation/approve_this_device_page.dart';

UndecryptableReason _reason(WidgetRef ref) {
  final facts = ref.watch(accountSecurityFactsProvider).value;
  if (facts == null) return UndecryptableReason.keyNeverShared;
  return undecryptableReason(
    keyBackupExists: facts.keyBackupExists,
    keyBackupUsableHere: facts.keyBackupUsableHere,
  );
}

class UndecryptableMessageContent extends ConsumerWidget {
  const UndecryptableMessageContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final copy = undecryptableCopy(_reason(ref));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                copy.text,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
        if (copy.offersRecovery)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ApproveThisDevicePage(),
                ),
              ),
              child: const Text('Unlock older messages'),
            ),
          ),
      ],
    );
  }
}

class UndecryptablePreviewText extends ConsumerWidget {
  const UndecryptablePreviewText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.lock_outline,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            undecryptableCopy(_reason(ref)).text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }
}
