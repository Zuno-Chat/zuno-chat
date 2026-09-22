import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/matrix/matrix_ids.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/security/verification_cancel_message.dart';
import 'qr_scanner_page.dart';

class VerificationPage extends StatefulWidget {
  final KeyVerification keyVerification;
  final bool isOwnDevice;

  const VerificationPage({
    required this.keyVerification,
    this.isOwnDevice = false,
    super.key,
  });

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  bool _methodChosen = false;

  @override
  void initState() {
    super.initState();
    widget.keyVerification.onUpdate = _onUpdate;
    _maybeAutoChooseMethod();
  }

  @override
  void dispose() {
    widget.keyVerification.onUpdate = null;
    if (!widget.keyVerification.isDone) {
      widget.keyVerification.cancel();
    }
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    _maybeAutoChooseMethod();
  }

  void _maybeAutoChooseMethod() {
    if (_methodChosen) return;
    final kv = widget.keyVerification;
    if (kv.state != KeyVerificationState.askChoice) return;
    if (_qrPossible) return;
    _methodChosen = true;
    kv.continueVerification(EventTypes.Sas);
  }

  bool get _qrPossible {
    final methods = widget.keyVerification.possibleMethods;
    return methods.contains(EventTypes.Reciprocate) ||
        methods.contains(EventTypes.QRShow) ||
        methods.contains(EventTypes.QRScan);
  }

  bool get _canScan {
    final methods = widget.keyVerification.possibleMethods;
    return methods.contains(EventTypes.QRScan) ||
        methods.contains(EventTypes.Reciprocate);
  }

  Future<void> _scan() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => QrScannerPage(
          title: widget.isOwnDevice
              ? 'Scan your other device'
              : 'Scan their code',
        ),
      ),
    );
    if (bytes == null || !mounted) return;
    _methodChosen = true;
    await widget.keyVerification.continueVerification(
      EventTypes.Reciprocate,
      qrDataRawBytes: bytes,
    );
  }

  void _useEmojiInstead() {
    _methodChosen = true;
    widget.keyVerification.continueVerification(EventTypes.Sas);
  }

  String get _subject => widget.isOwnDevice
      ? 'your other device'
      : withoutServer(widget.keyVerification.userId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isOwnDevice ? 'Approve this device' : 'Confirm it is them',
        ),
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final kv = widget.keyVerification;

    if (kv.canceled) return _stoppedMessage(kv, Icons.cancel_outlined);

    switch (kv.state) {
      case KeyVerificationState.askChoice:
        if (!_qrPossible) {
          return const _StatusMessage(
            spinner: true,
            title: 'Waiting for the other device…',
          );
        }
        final buffer = kv.qrCode?.qrDataRawBytes;
        return _QrChoiceScreen(
          qrData: buffer == null ? null : Uint8List.fromList(buffer),
          canScan: _canScan,
          isOwnDevice: widget.isOwnDevice,
          onScan: _scan,
          onUseEmoji: _useEmojiInstead,
        );

      case KeyVerificationState.askSas:
        return _SasComparison(
          emojis: kv.sasEmojis,
          isOwnDevice: widget.isOwnDevice,
          onMatch: kv.acceptSas,
          onNoMatch: kv.rejectSas,
        );

      case KeyVerificationState.showQRSuccess:
        return _StatusMessage(
          icon: Icons.check_circle_outline,
          title: 'Scanned',
          subtitle: widget.isOwnDevice
              ? 'Confirm on your other device to finish.'
              : 'Tell them it worked so they can finish on their side.',
        );

      case KeyVerificationState.confirmQRScan:
        return _ConfirmScanScreen(
          subject: _subject,
          onConfirm: kv.acceptQRScanConfirmation,
          onReject: () => kv.cancel('m.user'),
        );

      case KeyVerificationState.done:
        return _StatusMessage(
          icon: Icons.check_circle_outline,
          title: widget.isOwnDevice ? 'Approved' : 'Confirmed',
          subtitle: widget.isOwnDevice
              ? 'This device can now read your messages.'
              : 'You are talking to the real $_subject. You will not need to '
                    'do this again, even if they get a new device.',
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.isOwnDevice ? 'Done' : 'Back to chat'),
          ),
        );

      case KeyVerificationState.error:
        return _stoppedMessage(kv, Icons.error_outline);

      case KeyVerificationState.askSSSS:
        return const _StatusMessage(
          icon: Icons.lock_outline,
          title: 'Unlock this device first',
          subtitle:
              'Go to Settings, then Security, and enter your recovery code. '
              'Then try again.',
        );

      case KeyVerificationState.waitingAccept:
      case KeyVerificationState.waitingSas:
      case KeyVerificationState.askAccept:
        return const _StatusMessage(
          spinner: true,
          title: 'Waiting for the other device…',
        );
    }
  }

  Widget _stoppedMessage(KeyVerification kv, IconData fallbackIcon) {
    final message = verificationCancelMessage(
      code: kv.canceledCode,
      reason: kv.canceledReason,
      isOwnDevice: widget.isOwnDevice,
    );
    return _StatusMessage(
      icon: message.isAlarming ? attentionIcon : fallbackIcon,
      title: message.title,
      subtitle: message.body,
    );
  }
}

class _QrChoiceScreen extends StatelessWidget {
  final Uint8List? qrData;
  final bool canScan;
  final bool isOwnDevice;
  final VoidCallback onScan;
  final VoidCallback onUseEmoji;

  const _QrChoiceScreen({
    required this.qrData,
    required this.canScan,
    required this.isOwnDevice,
    required this.onScan,
    required this.onUseEmoji,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          isOwnDevice
              ? 'Scan this with your other device'
              : 'Let them scan this',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (qrData != null)
          Center(child: _QrImage(data: qrData!))
        else
          const _StatusMessage(spinner: true, title: 'Preparing a code…'),
        const SizedBox(height: 24),
        if (canScan) ...[
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_scanner_outlined),
            label: Text(
              isOwnDevice ? 'Scan the other device' : 'Scan their code',
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextButton(
          onPressed: onUseEmoji,
          child: const Text('Not together? Compare pictures instead'),
        ),
      ],
    );
  }
}

class _QrImage extends StatelessWidget {
  final Uint8List data;

  const _QrImage({required this.data});

  @override
  Widget build(BuildContext context) {
    final qr = QrCode.fromUint8List(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: SizedBox(
        width: 240,
        height: 240,
        child: CustomPaint(
          painter: QrPainter.withQr(
            qr: qr,
            gapless: true,
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmScanScreen extends StatelessWidget {
  final String subject;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const _ConfirmScanScreen({
    required this.subject,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_2_outlined, size: 48),
          const SizedBox(height: 24),
          Text(
            'Did their screen show a check mark?',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            '$subject scanned your code. Check their screen says it '
            'worked before you finish.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(onPressed: onConfirm, child: const Text('Yes, finish')),
          const SizedBox(height: 8),
          TextButton(onPressed: onReject, child: const Text('No, stop')),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  final IconData? icon;
  final bool spinner;
  final String title;
  final String? subtitle;
  final Widget? action;

  const _StatusMessage({
    this.icon,
    this.spinner = false,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              const CircularProgressIndicator()
            else if (icon != null)
              Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 32), action!],
          ],
        ),
      ),
    );
  }
}

class _SasComparison extends StatelessWidget {
  final List<KeyVerificationEmoji> emojis;
  final bool isOwnDevice;
  final VoidCallback onMatch;
  final VoidCallback onNoMatch;

  const _SasComparison({
    required this.emojis,
    required this.isOwnDevice,
    required this.onMatch,
    required this.onNoMatch,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          isOwnDevice
              ? 'Check these match on both devices'
              : 'Check these match. Read them out to each other.',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: [
            for (final emoji in emojis)
              SizedBox(
                width: 72,
                child: Column(
                  children: [
                    Text(emoji.emoji, style: const TextStyle(fontSize: 32)),
                    const SizedBox(height: 4),
                    Text(
                      emoji.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 32),
        FilledButton(onPressed: onMatch, child: const Text('They match')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onNoMatch,
          child: const Text('They do not match'),
        ),
      ],
    );
  }
}
