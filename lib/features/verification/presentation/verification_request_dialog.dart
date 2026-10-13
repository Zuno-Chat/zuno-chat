import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';

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
    return AlertDialog(
      title: const Text('Verification request'),
      content: Text(
        '${withoutServer(_request.userId)} wants to verify with you.',
      ),
      actions: [
        TextButton(
          onPressed: () => _answer(false),
          child: const Text('Decline'),
        ),
        TextButton(onPressed: () => _answer(true), child: const Text('Accept')),
      ],
    );
  }
}
