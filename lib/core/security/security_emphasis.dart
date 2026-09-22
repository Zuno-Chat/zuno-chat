import 'package:flutter/material.dart';

const attentionIcon = Icons.warning_rounded;
const settledIcon = Icons.check_circle_outline;
const notEncryptedIcon = Icons.no_encryption;

const attentionStripeWidth = 4.0;

const deviceApprovedIcon = Icons.verified_user;
const deviceUnapprovedIcon = Icons.gpp_maybe;

Color deviceApprovedColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF81C784)
    : const Color(0xFF2E7D32);

Color deviceUnapprovedColor(BuildContext context) =>
    Theme.of(context).colorScheme.error;

IconData securityStatusIcon({required bool attention}) =>
    attention ? attentionIcon : settledIcon;

class AttentionStripe extends StatelessWidget {
  const AttentionStripe({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: attentionStripeWidth,
    color: Theme.of(context).colorScheme.error,
  );
}
