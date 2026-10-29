import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:qr_flutter/qr_flutter.dart' show QrCode, QrErrorCorrectLevel;

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/linked_sign_in.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/uia_cancel.dart';
import '../../../core/security/screen_security_service.dart';
import '../../../core/ui/qr_image.dart';
import 'uia_password_prompt.dart';

class SignInAnotherDevicePage extends ConsumerStatefulWidget {
  const SignInAnotherDevicePage({super.key});

  @override
  ConsumerState<SignInAnotherDevicePage> createState() =>
      _SignInAnotherDevicePageState();
}

class _SignInAnotherDevicePageState
    extends ConsumerState<SignInAnotherDevicePage>
    with ScreenProtected<SignInAnotherDevicePage> {
  ({IssuedSignInCode issued, QrCode qr})? _shown;
  String? _error;
  bool _expired = false;
  StreamSubscription<UiaRequest>? _uiaSub;

  @override
  void initState() {
    super.initState();
    final client = ref.read(matrixClientProvider);
    _uiaSub = client.onUiaRequest.stream.listen(_handleUia);
    unawaited(_request());
  }

  @override
  void dispose() {
    _uiaSub?.cancel();
    super.dispose();
  }

  Future<void> _handleUia(UiaRequest uia) => answerUiaWithPassword(
    context,
    uia,
    userId: ref.read(matrixClientProvider).userID!,
  );

  Future<void> _request() async {
    setState(() {
      _shown = null;
      _error = null;
      _expired = false;
    });
    final client = ref.read(matrixClientProvider);
    try {
      final issued = await issueLinkedSignInCode(client);
      if (!mounted) return;
      final qr = QrCode.fromData(
        data: issued.code.encode(),
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      setState(() => _shown = (issued: issued, qr: qr));
    } catch (e, s) {
      final unsupported =
          e is MatrixException && e.error == MatrixError.M_UNRECOGNIZED;
      if (!isUiaCancel(e) && !unsupported) {
        reportCaught('issue sign-in code', e, s);
      }
      if (!mounted) return;
      if (isUiaCancel(e)) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _error = signInCodeIssueErrorMessage(context.l10n, e));
    }
  }

  List<Widget> _body(BuildContext context) {
    final l10n = context.l10n;
    final error = _error;
    final shown = _shown;
    if (error != null) {
      return [
        Text(error, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: _request, child: Text(l10n.commonTryAgain)),
      ];
    }
    if (shown == null) {
      return const [Center(child: CircularProgressIndicator())];
    }
    if (_expired) {
      return [
        Text(l10n.settingsSignInExpired, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _request,
          child: Text(l10n.settingsSignInNewCode),
        ),
      ];
    }
    final theme = Theme.of(context);
    return [
      Text(l10n.settingsSignInScan, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      Center(child: QrImage(shown.qr)),
      const SizedBox(height: 16),
      Text(
        shown.issued.code.typed,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 8),
      _Countdown(
        expiresAt: shown.issued.expiresAt,
        onExpired: () => setState(() => _expired = true),
      ),
      const SizedBox(height: 16),
      Text(l10n.settingsSignInWorksOnce, textAlign: TextAlign.center),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsSignInTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: _body(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Countdown extends StatefulWidget {
  final DateTime expiresAt;
  final VoidCallback onExpired;

  const _Countdown({required this.expiresAt, required this.onExpired});

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late Duration _remaining = _left();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _left() {
    final left = widget.expiresAt.difference(clock.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _tick() {
    final left = _left();
    if (left == Duration.zero) {
      _ticker?.cancel();
      widget.onExpired();
      return;
    }
    setState(() => _remaining = left);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _remaining.inMinutes;
    final seconds = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return Text(
      context.l10n.settingsSignInExpiresIn(minutes, seconds),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
