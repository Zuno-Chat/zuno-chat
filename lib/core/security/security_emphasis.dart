import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../ui/zuno_colors.dart';

const attentionIcon = Icons.warning_rounded;
const settledIcon = Icons.check_circle_outline;
const notEncryptedIcon = Icons.no_encryption;

const deviceApprovedIcon = Icons.verified_user;
const deviceUnapprovedIcon = Icons.gpp_maybe;

Color deviceApprovedColor(BuildContext context) =>
    ZunoColors.of(context).success;

Color deviceUnapprovedColor(BuildContext context) =>
    Theme.of(context).colorScheme.error;

Color notEncryptedColor(BuildContext context) =>
    Theme.of(context).colorScheme.error;

IconData securityStatusIcon({required bool attention}) =>
    attention ? attentionIcon : settledIcon;

class NotEncryptedMark extends StatelessWidget {
  final double? size;

  const NotEncryptedMark({this.size, super.key});

  @override
  Widget build(BuildContext context) => Icon(
    notEncryptedIcon,
    size: size,
    color: notEncryptedColor(context),
    semanticLabel: context.l10n.roomInfoNotEncrypted,
  );
}
