import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class QrScannerPage extends StatefulWidget {
  final String title;

  const QrScannerPage({this.title = 'Scan their code', super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  bool? _permitted;

  @override
  void initState() {
    super.initState();
    unawaited(_requestCamera());
  }

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (mounted) setState(() => _permitted = status.isGranted);
  }

  @override
  void dispose() {
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
      DecodedVisionBarcodeBytes(:final bytes, :final rawBytes) =>
        bytes ?? rawBytes,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Zuno needs the camera to scan the code. You can still '
              'compare pictures instead.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: openAppSettings,
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            color: Colors.black54,
            padding: const EdgeInsets.all(24),
            child: const Text(
              'Point the camera at the code on the other device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
