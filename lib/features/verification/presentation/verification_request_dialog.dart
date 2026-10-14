import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/ui/close_own_route.dart';

class VerificationRequestDialog extends StatefulWidget {
  final KeyVerification keyVerification;

  const VerificationRequestDialog({required this.keyVerification, super.key});

  @override
  State<VerificationRequestDialog> createState() =>
      _VerificationRequestDialogState();
}

class _VerificationRequestDialogState extends State<VerificationRequestDialog> {
  KeyVerification get _request => widget.keyVerification;

  bool get _watching => _request.onUpdate == _dismissOnceStopped;

  @override
  void initState() {
    super.initState();
    _request.onUpdate = _dismissOnceStopped;
    WidgetsBinding.instance.addPostFrameCallback((_) => _dismissOnceStopped());
  }

  @override
  void dispose() {
    _stopWatching();
    super.dispose();
  }

  void _stopWatching() {
    if (_watching) _request.onUpdate = null;
  }

  void _dismissOnceStopped() {
    if (!mounted || !_watching || !_request.isDone) return;
    _stopWatching();
    closeOwnRoute(context);
  }

  void _answer(bool accept) {
    _stopWatching();
    Navigator.of(context).pop(accept);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.verificationRequestTitle),
      content: Text(
        l10n.verificationRequestBody(withoutServer(_request.userId)),
      ),
      actions: [
        TextButton(
          onPressed: () => _answer(false),
          child: Text(l10n.commonDecline),
        ),
        TextButton(
          onPressed: () => _answer(true),
          child: Text(l10n.verificationAccept),
        ),
      ],
    );
  }
}
