import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/verification/presentation/qr_scanner_page.dart';

void main() {
  Future<void> pumpCaption(WidgetTester tester, {required double inset}) {
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(padding: EdgeInsets.only(bottom: inset)),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ScannerCaption('Point the camera at the code.'),
          ),
        ),
      ),
    );
  }

  testWidgets('the text sits above the navigation bar, the band behind it', (
    tester,
  ) async {
    await pumpCaption(tester, inset: 48);

    final screen = tester.getRect(find.byType(Align));
    final band = tester.getRect(find.byType(ScannerCaption));
    final text = tester.getRect(find.text('Point the camera at the code.'));

    expect(band.bottom, screen.bottom);
    expect(text.bottom, lessThanOrEqualTo(screen.bottom - 48 - 24));
  });

  testWidgets('without a navigation bar only the padding remains', (
    tester,
  ) async {
    await pumpCaption(tester, inset: 0);

    final screen = tester.getRect(find.byType(Align));
    final text = tester.getRect(find.text('Point the camera at the code.'));

    expect(text.bottom, screen.bottom - 24);
  });
}
