import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../ui/avatar_mark.dart';
import 'security_emphasis.dart';
import 'security_providers.dart';
import 'user_trust.dart';

class ConfirmedPersonMark extends ConsumerWidget {
  final String userId;
  final Widget orElse;

  const ConfirmedPersonMark({
    required this.userId,
    this.orElse = const SizedBox.shrink(),
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!userTrustConfirmed(ref.watch(userTrustProvider(userId)))) {
      return orElse;
    }
    return AvatarMark(
      icon: confirmedPersonIcon,
      color: confirmedPersonColor(context),
      semanticLabel: context.l10n.chatConfirmedLabel,
    );
  }
}
