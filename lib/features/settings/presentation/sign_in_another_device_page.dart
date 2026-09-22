import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/matrix/linked_sign_in.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/security/screen_security_service.dart';
import '../../../core/settings/app_preferences_provider.dart';
import 'uia_password_prompt.dart';

class SignInAnotherDevicePage extends ConsumerStatefulWidget {
  final DateTime Function() now;

  const SignInAnotherDevicePage({this.now = DateTime.now, super.key});

  @override
  ConsumerState<SignInAnotherDevicePage> createState() =>
      _SignInAnotherDevicePageState();
}

class _SignInAnotherDevicePageState
    extends ConsumerState<SignInAnotherDevicePage> {
  IssuedSignInCode? _issued;
  String? _error;
  bool _expired = false;
  StreamSubscription<UiaRequest>? _uiaSub;
  bool _screenshotsBlockedByPreference = false;

  @override
  void initState() {
    super.initState();
    final client = ref.read(matrixClientProvider);
    _uiaSub = client.onUiaRequest.stream.listen(_handleUia);
    _screenshotsBlockedByPreference = ref.read(preventScreenshotsProvider);
    unawaited(ScreenSecurityService.instance.setPreventScreenshots(true));
    unawaited(_request());
  }

  @override
  void dispose() {
    _uiaSub?.cancel();
    unawaited(
      ScreenSecurityService.instance.setPreventScreenshots(
        _screenshotsBlockedByPreference,
      ),
    );
    super.dispose();
  }

  Future<void> _handleUia(UiaRequest uia) async {
    if (uia.state != UiaRequestState.waitForUser) return;
    final client = ref.read(matrixClientProvider);
    final password = await askPasswordForUia(context);
    if (!mounted) return;
    if (password == null || password.isEmpty) {
      uia.cancel();
      return;
    }
    await uia.completeStage(
      AuthenticationPassword(
        session: uia.session,
        password: password,
        identifier: AuthenticationUserIdentifier(user: client.userID!),
      ),
    );
  }

  Future<void> _request() async {
    setState(() {
      _issued = null;
      _error = null;
      _expired = false;
    });
    final client = ref.read(matrixClientProvider);
    try {
      final issued = await issueLinkedSignInCode(client, now: widget.now);
      if (!mounted) return;
      setState(() => _issued = issued);
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('canceled')) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _error = signInCodeIssueErrorMessage(e));
    }
  }

  List<Widget> _body(BuildContext context) {
    final error = _error;
    final issued = _issued;
    if (error != null) {
      return [
        Text(error, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: _request, child: const Text('Try again')),
      ];
    }
    if (issued == null) {
      return const [Center(child: CircularProgressIndicator())];
    }
    if (_expired) {
      return [
        const Text('This code has expired.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: _request, child: const Text('New code')),
      ];
    }
    final theme = Theme.of(context);
    return [
      const Text(
        'Scan this with the new device, or type the code under it.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      Center(child: _QrImage(data: issued.code.encode())),
      const SizedBox(height: 16),
      Text(
        groupedSignInCode(issued.code.token),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 8),
      _Countdown(
        expiresAt: issued.expiresAt,
        now: widget.now,
        onExpired: () => setState(() => _expired = true),
      ),
      const SizedBox(height: 16),
      const Text(
        'It works once. Anyone who sees it can sign in to your account.',
        textAlign: TextAlign.center,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in on another device')),
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
  final DateTime Function() now;
  final VoidCallback onExpired;

  const _Countdown({
    required this.expiresAt,
    required this.now,
    required this.onExpired,
  });

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
    final left = widget.expiresAt.difference(widget.now());
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
      'Expires in $minutes:$seconds',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _QrImage extends StatelessWidget {
  final String data;

  const _QrImage({required this.data});

  @override
  Widget build(BuildContext context) {
    final qr = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
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
