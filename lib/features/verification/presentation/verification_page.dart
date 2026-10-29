import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:qr_flutter/qr_flutter.dart' show QrCode, QrErrorCorrectLevel;

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/verification_cancel_message.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/qr_image.dart';
import '../../../core/ui/status_message.dart';
import 'qr_scanner_page.dart';

class VerificationPage extends ConsumerStatefulWidget {
  final KeyVerification keyVerification;
  final bool isOwnDevice;
  final bool picturesFirst;

  const VerificationPage({
    required this.keyVerification,
    this.isOwnDevice = false,
    this.picturesFirst = false,
    super.key,
  });

  @override
  ConsumerState<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends ConsumerState<VerificationPage> {
  bool _methodChosen = false;
  bool _sending = false;
  QRCode? _qrSource;
  QrCode? _qr;

  @override
  void initState() {
    super.initState();
    widget.keyVerification.onUpdate = _onUpdate;
    _maybeAutoChooseMethod();
  }

  @override
  void dispose() {
    final kv = widget.keyVerification;
    kv.onUpdate = null;
    if (!kv.isDone) {
      unawaited(
        runBestEffort(
          () => kv.cancel('m.user'),
          label: 'cancel verification on leave',
        ),
      );
    }
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    _maybeAutoChooseMethod();
    _rememberConfirmedPerson();
  }

  void _rememberConfirmedPerson() {
    final kv = widget.keyVerification;
    if (kv.state != KeyVerificationState.done &&
        kv.state != KeyVerificationState.askSSSS) {
      return;
    }
    final client = ref.read(matrixClientProvider);
    if (kv.userId == client.userID) return;
    final identity = client.userDeviceKeys[kv.userId]?.masterKey;
    final key = identity?.ed25519Key;
    if (identity == null || key == null || !identity.directVerified) return;
    final store = ref.read(confirmedIdentityStoreProvider);
    unawaited(
      runBestEffort(
        () => store.remember(kv.userId, key),
        label: 'remember a confirmed person',
      ),
    );
  }

  Future<void> _send(String label, Future<void> Function() request) async {
    if (_sending) return;
    _sending = true;
    try {
      await attempt(
        context,
        request,
        label: label,
        failed: context.l10n.verificationCouldNotSend,
      );
    } finally {
      _sending = false;
    }
  }

  void _maybeAutoChooseMethod() {
    if (_methodChosen) return;
    final kv = widget.keyVerification;
    if (kv.state != KeyVerificationState.askChoice) return;
    if (_offersQr) return;
    _methodChosen = true;
    unawaited(_startPicturesOrStop());
  }

  Future<void> _startPicturesOrStop() async {
    final kv = widget.keyVerification;
    try {
      await kv.continueVerification(EventTypes.Sas);
    } catch (e, s) {
      reportCaught('start picture check', e, s);
      if (kv.isDone) return;
      await runBestEffort(kv.cancel, label: 'cancel unstartable verification');
      if (!kv.isDone) await kv.cancel('m.unknown', true);
    }
  }

  QrCode? get _ownCode {
    final kv = widget.keyVerification;
    if (!kv.possibleMethods.contains(EventTypes.QRShow)) return null;
    final source = kv.qrCode;
    if (source == null) return null;
    if (!identical(source, _qrSource)) {
      _qrSource = source;
      _qr = QrCode.fromUint8List(
        data: Uint8List.fromList(source.qrDataRawBytes),
        errorCorrectLevel: QrErrorCorrectLevel.L,
      );
    }
    return _qr;
  }

  bool get _canScan =>
      widget.keyVerification.possibleMethods.contains(EventTypes.QRScan);

  bool get _offersQr => !widget.picturesFirst && (_ownCode != null || _canScan);

  Future<void> _scan() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => QrScannerPage(
          title: widget.isOwnDevice
              ? context.l10n.verificationScanOtherDeviceTitle
              : context.l10n.verificationScanTheirCode,
        ),
      ),
    );
    if (bytes == null || !mounted) return;
    final kv = widget.keyVerification;
    if (kv.canceled || kv.state != KeyVerificationState.askChoice) return;
    _methodChosen = true;
    await _send(
      'send scanned code',
      () => kv.continueVerification(
        EventTypes.Reciprocate,
        qrDataRawBytes: bytes,
      ),
    );
  }

  void _useEmojiInstead() {
    _methodChosen = true;
    unawaited(
      _send(
        'start picture check',
        () => widget.keyVerification.continueVerification(EventTypes.Sas),
      ),
    );
  }

  String get _subject => withoutServer(widget.keyVerification.userId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isOwnDevice
              ? context.l10n.verificationApproveTitle
              : context.l10n.verificationConfirmTitle,
        ),
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final kv = widget.keyVerification;
    final l10n = context.l10n;

    if (kv.canceled) return _stoppedMessage(kv, Icons.cancel_outlined);

    switch (kv.state) {
      case KeyVerificationState.askChoice:
        if (!_offersQr) {
          return StatusMessage.busy(title: l10n.verificationWaitingForOther);
        }
        return _QrChoiceScreen(
          qr: _ownCode,
          canScan: _canScan,
          isOwnDevice: widget.isOwnDevice,
          onScan: _scan,
          onUseEmoji: _useEmojiInstead,
        );

      case KeyVerificationState.askSas:
        return _SasComparison(
          emojis: kv.sasEmojis,
          isOwnDevice: widget.isOwnDevice,
          onMatch: () => _send('accept pictures', kv.acceptSas),
          onNoMatch: () => _send('reject pictures', kv.rejectSas),
        );

      case KeyVerificationState.showQRSuccess:
        return StatusMessage(
          icon: Icons.check_circle_outline,
          title: l10n.verificationScanned,
          body: widget.isOwnDevice
              ? l10n.verificationScannedOwn
              : l10n.verificationScannedOther,
        );

      case KeyVerificationState.confirmQRScan:
        return _ConfirmScanScreen(
          subject: _subject,
          isOwnDevice: widget.isOwnDevice,
          onConfirm: () => _send('confirm scan', kv.acceptQRScanConfirmation),
          onReject: () => _send('reject scan', () => kv.cancel('m.user')),
        );

      case KeyVerificationState.done:
        return StatusMessage(
          icon: Icons.check_circle_outline,
          title: widget.isOwnDevice
              ? l10n.verificationApproved
              : l10n.verificationConfirmed,
          body: widget.isOwnDevice
              ? l10n.verificationApprovedBody
              : l10n.verificationConfirmedBody(_subject),
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              widget.isOwnDevice
                  ? l10n.commonDone
                  : l10n.verificationBackToChat,
            ),
          ),
        );

      case KeyVerificationState.error:
        return _stoppedMessage(kv, Icons.error_outline);

      case KeyVerificationState.askSSSS:
        return StatusMessage(
          icon: Icons.lock_outline,
          title: l10n.verificationUnlockFirst,
          body: l10n.verificationUnlockFirstBody,
        );

      case KeyVerificationState.waitingAccept:
      case KeyVerificationState.waitingSas:
      case KeyVerificationState.askAccept:
        return StatusMessage.busy(title: l10n.verificationWaitingForOther);
    }
  }

  Widget _stoppedMessage(KeyVerification kv, IconData fallbackIcon) {
    final message = verificationCancelMessage(
      context.l10n,
      code: kv.canceledCode,
      isOwnDevice: widget.isOwnDevice,
    );
    return StatusMessage(
      icon: message.isAlarming ? attentionIcon : fallbackIcon,
      title: message.title,
      body: message.body,
    );
  }
}

class _QrChoiceScreen extends StatelessWidget {
  final QrCode? qr;
  final bool canScan;
  final bool isOwnDevice;
  final VoidCallback onScan;
  final VoidCallback onUseEmoji;

  const _QrChoiceScreen({
    required this.qr,
    required this.canScan,
    required this.isOwnDevice,
    required this.onScan,
    required this.onUseEmoji,
  });

  String _title(AppLocalizations l10n) {
    if (qr != null) {
      return isOwnDevice
          ? l10n.verificationQrOwnTitle
          : l10n.verificationQrOtherTitle;
    }
    return isOwnDevice
        ? l10n.verificationScanOwnScreenTitle
        : l10n.verificationScanOtherScreenTitle;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          _title(context.l10n),
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (qr case final qr?) ...[
          Center(child: QrImage(qr)),
          const SizedBox(height: 24),
        ],
        if (canScan) ...[
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_scanner_outlined),
            label: Text(
              isOwnDevice
                  ? context.l10n.verificationScanOtherDevice
                  : context.l10n.verificationScanTheirCode,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextButton(
          onPressed: onUseEmoji,
          child: Text(context.l10n.verificationComparePictures),
        ),
      ],
    );
  }
}

class _ConfirmScanScreen extends StatelessWidget {
  final String subject;
  final bool isOwnDevice;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const _ConfirmScanScreen({
    required this.subject,
    required this.isOwnDevice,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_2_outlined, size: 48),
          const SizedBox(height: 24),
          Text(
            isOwnDevice
                ? l10n.verificationCheckOwnQuestion
                : l10n.verificationCheckOtherQuestion,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            isOwnDevice
                ? l10n.verificationCheckOwnBody
                : l10n.verificationCheckOtherBody(subject),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: onConfirm,
            child: Text(l10n.verificationYesFinish),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onReject, child: Text(l10n.verificationNoStop)),
        ],
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
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          isOwnDevice
              ? l10n.verificationCompareOwn
              : l10n.verificationCompareOther,
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
        FilledButton(
          onPressed: onMatch,
          child: Text(l10n.verificationTheyMatch),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onNoMatch,
          child: Text(l10n.verificationTheyDoNotMatch),
        ),
      ],
    );
  }
}
