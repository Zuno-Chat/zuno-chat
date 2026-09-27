import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/errors/best_effort.dart';

class QrScannerPage extends StatefulWidget {
  final String title;
  final String withoutCamera;

  const QrScannerPage({
    this.title = 'Scan their code',
    this.withoutCamera = 'You can still compare pictures instead.',
    super.key,
  });

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  bool? _permitted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_resolveCamera(Permission.camera.request));
  }

  Future<void> _resolveCamera(Future<PermissionStatus> Function() read) async {
    var granted = false;
    try {
      granted = (await read()).isGranted;
    } catch (e) {
      logCaught('camera permission', e);
    }
    if (mounted) setState(() => _permitted = granted);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _permitted == false) {
      unawaited(_resolveCamera(() => Permission.camera.status));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final bytes = _bytesOf(barcode.rawDecodedBytes);
      if (bytes == null || bytes.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(bytes);
      return;
    }
  }

  Uint8List? _bytesOf(BarcodeBytes? bytes) {
    return switch (bytes) {
      DecodedBarcodeBytes(:final bytes) => bytes,
      DecodedVisionBarcodeBytes(:final bytes) => bytes,
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: switch (_permitted) {
        null => const Center(child: CircularProgressIndicator()),
        false => _buildDenied(),
        true => _buildScanner(),
      },
    );
  }

  Widget _buildDenied() {
    return _ScannerNotice(
      text: 'Zuno needs the camera to scan the code. ${widget.withoutCamera}',
      action: const OutlinedButton(
        onPressed: openAppSettings,
        child: Text('Open settings'),
      ),
    );
  }

  Widget _buildFailed(BuildContext context, MobileScannerException error) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: error.errorCode == MobileScannerErrorCode.permissionDenied
          ? _buildDenied()
          : _ScannerNotice(
              title: 'The camera did not start',
              text:
                  'Another app may be using it. Go back and try again. '
                  '${widget.withoutCamera}',
            ),
    );
  }

  Widget _buildScanner() {
    return MobileScanner(
      controller: _controller,
      onDetect: _onDetect,
      errorBuilder: _buildFailed,
      overlayBuilder: (_, _) => const Align(
        alignment: Alignment.bottomCenter,
        child: ScannerCaption(
          'Point the camera at the code on the other device.',
        ),
      ),
    );
  }
}

class _ScannerNotice extends StatelessWidget {
  final String? title;
  final String text;
  final Widget? action;

  const _ScannerNotice({this.title, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 48),
            const SizedBox(height: 16),
            if (title case final title?) ...[
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            Text(text, textAlign: TextAlign.center),
            if (action case final action?) ...[
              const SizedBox(height: 24),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

class ScannerCaption extends StatelessWidget {
  final String text;

  const ScannerCaption(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black54,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
