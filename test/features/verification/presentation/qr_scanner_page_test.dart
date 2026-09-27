import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:zuno/features/verification/presentation/qr_scanner_page.dart';

import 'verification_harness.dart';

const _needsCamera = 'Zuno needs the camera to scan the code.';
const _pointCamera = 'Point the camera at the code on the other device.';

void main() {
  late FakeScannerPlatform scanner;
  late FakeCameraPermission permission;
  late List<Uint8List?> results;

  setUp(() {
    scanner = installFakeScanner();
    permission = installFakeCameraPermission();
    results = [];
  });

  Future<void> open(
    WidgetTester tester, {
    QrScannerPage page = const QrScannerPage(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(
                await Navigator.of(context)
                    .push<Uint8List>(MaterialPageRoute(builder: (_) => page)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
  }

  group('camera permission', () {
    testWidgets('waits for the answer before showing anything else', (
      tester,
    ) async {
      permission.requestGate = Completer<void>();
      await open(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(MobileScanner), findsNothing);
      expect(find.textContaining(_needsCamera), findsNothing);

      permission.requestGate!.complete();
      await settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(MobileScanner), findsOneWidget);
    });

    testWidgets('granted starts the camera under a caption', (tester) async {
      await open(tester, page: const QrScannerPage(title: 'Scan it'));

      expect(find.text('Scan it'), findsOneWidget);
      expect(find.byType(MobileScanner), findsOneWidget);
      expect(find.text(_pointCamera), findsOneWidget);
      expect(scanner.starts, 1);
    });

    testWidgets('the title defaults to scanning a person', (tester) async {
      await open(tester);
      expect(find.text('Scan their code'), findsOneWidget);
    });

    for (final (name, status) in [
      ('denied', permissionDenied),
      ('denied for good', permissionPermanentlyDenied),
    ]) {
      testWidgets('$name explains and offers settings', (tester) async {
        permission.onRequest = status;
        await open(tester);

        expect(find.byType(MobileScanner), findsNothing);
        expect(find.textContaining(_needsCamera), findsOneWidget);
        expect(
          find.textContaining('You can still compare pictures instead.'),
          findsOneWidget,
        );

        await tester.tap(find.text('Open settings'));
        await tester.pump();

        expect(permission.calls, contains('openAppSettings'));
      });
    }

    testWidgets('the way around a refusal is worded by the caller', (
      tester,
    ) async {
      permission.onRequest = permissionDenied;
      await open(
        tester,
        page: const QrScannerPage(
          withoutCamera: 'You can still type the code instead.',
        ),
      );

      expect(
        find.textContaining('You can still type the code instead.'),
        findsOneWidget,
      );
      expect(find.textContaining('compare pictures'), findsNothing);
    });

    testWidgets('a request that fails reads as refused, not as loading', (
      tester,
    ) async {
      permission.requestThrows = true;
      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining(_needsCamera), findsOneWidget);
    });

    testWidgets('allowing the camera in settings starts it on the way back', (
      tester,
    ) async {
      permission.onRequest = permissionPermanentlyDenied;
      await open(tester);
      expect(find.textContaining(_needsCamera), findsOneWidget);

      permission.onCheck = permissionGranted;
      await resume(tester);

      expect(find.textContaining(_needsCamera), findsNothing);
      expect(find.byType(MobileScanner), findsOneWidget);
    });

    testWidgets('coming back without allowing it changes nothing', (
      tester,
    ) async {
      permission.onRequest = permissionDenied;
      permission.onCheck = permissionDenied;
      await open(tester);

      await resume(tester);

      expect(find.textContaining(_needsCamera), findsOneWidget);
      expect(find.byType(MobileScanner), findsNothing);
    });

    testWidgets('a running camera is not asked about again on resume', (
      tester,
    ) async {
      await open(tester);
      permission.calls.clear();

      await resume(tester);

      expect(permission.calls, isEmpty);
      expect(find.byType(MobileScanner), findsOneWidget);
    });
  });

  group('scanning', () {
    testWidgets('a code closes the page with its bytes', (tester) async {
      await open(tester);

      scanner.scan([decoded(matrixQrBytes)]);
      await settle(tester);

      expect(find.byType(QrScannerPage), findsNothing);
      expect(results.single, matrixQrBytes);
    });

    testWidgets('codes without bytes are skipped for the first that has some', (
      tester,
    ) async {
      await open(tester);

      scanner.scan([
        null,
        decoded([]),
        decoded([7, 8, 9]),
        decoded([1]),
      ]);
      await settle(tester);

      expect(results.single, [7, 8, 9]);
    });

    testWidgets('a frame with nothing readable keeps the camera open', (
      tester,
    ) async {
      await open(tester);

      scanner.scan([null, decoded([])]);
      scanner.scan([]);
      await settle(tester);

      expect(find.byType(QrScannerPage), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('only the first code counts', (tester) async {
      await open(tester);

      scanner.scan([
        decoded([1, 2]),
      ]);
      scanner.scan([
        decoded([3, 4]),
      ]);
      await settle(tester);

      expect(results.single, [1, 2]);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('an Apple code uses its decoded bytes', (tester) async {
      await open(tester);

      scanner.scan([
        DecodedVisionBarcodeBytes(
          bytes: Uint8List.fromList([5, 6]),
          rawBytes: Uint8List.fromList([64, 5, 6, 0]),
        ),
      ]);
      await settle(tester);

      expect(results.single, [5, 6]);
    });

    testWidgets('an Apple code that could not be decoded is skipped, never '
        'returned with its header', (tester) async {
      await open(tester);

      scanner.scan([
        DecodedVisionBarcodeBytes(rawBytes: Uint8List.fromList([64, 5, 6, 0])),
      ]);
      await settle(tester);

      expect(find.byType(QrScannerPage), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('going back returns nothing and releases the camera', (
      tester,
    ) async {
      await open(tester);

      await tester.pageBack();
      await settle(tester);

      expect(results.single, isNull);
      expect(scanner.disposals, 1);
    });
  });

  group('a camera that does not start', () {
    testWidgets('says so in plain words', (tester) async {
      scanner.startError = const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(message: 'CAMERA_ERROR'),
      );
      await open(tester);

      expect(find.text('The camera did not start'), findsOneWidget);
      expect(find.textContaining('CAMERA_ERROR'), findsNothing);
      expect(find.text(_pointCamera), findsNothing);
    });

    testWidgets('a refusal the camera reports reads like any other refusal', (
      tester,
    ) async {
      scanner.startError = const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
      await open(tester);

      expect(find.textContaining(_needsCamera), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    });
  });
}
