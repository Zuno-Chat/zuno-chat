import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrImage extends StatelessWidget {
  final QrCode qr;

  const QrImage(this.qr, {super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox.square(
        dimension: 240,
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
    ),
  );
}
