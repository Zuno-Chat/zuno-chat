import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:typed_data/typed_data.dart';

const showAndScan = [
  EventTypes.Sas,
  EventTypes.Reciprocate,
  EventTypes.QRShow,
  EventTypes.QRScan,
];
const showOnly = [EventTypes.Sas, EventTypes.Reciprocate, EventTypes.QRShow];
const scanOnly = [EventTypes.Sas, EventTypes.Reciprocate, EventTypes.QRScan];

final matrixQrBytes = [...'MATRIX'.codeUnits, 2, 0, 0xff, 0x00, 0x80];

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

List<KeyVerificationEmoji> testEmojis() =>
    List.generate(7, KeyVerificationEmoji.new);

class FakeKeyVerification extends Fake implements KeyVerification {
  FakeKeyVerification({
    this.userId = '@bob:example.org',
    this.state = KeyVerificationState.waitingAccept,
    this.possibleMethods = const [EventTypes.Sas],
    List<int>? qrBytes,
    this.sasEmojis = const [],
  }) : qrCode = qrBytes == null
           ? null
           : QRCode('secret', Uint8Buffer()..addAll(qrBytes));

  final calls = <String>[];
  final scanned = <Uint8List>[];
  Object? sendError;
  Completer<void>? sendGate;

  @override
  final String userId;

  @override
  KeyVerificationState state;

  @override
  bool canceled = false;

  @override
  String? canceledCode;

  @override
  String? canceledReason;

  @override
  List<String> possibleMethods;

  @override
  QRCode? qrCode;

  @override
  void Function()? onUpdate;

  @override
  final List<KeyVerificationEmoji> sasEmojis;

  @override
  bool get isDone =>
      canceled ||
      state == KeyVerificationState.error ||
      state == KeyVerificationState.done;

  void moveTo(KeyVerificationState next) {
    state = next;
    onUpdate?.call();
  }

  void stopWith(String code, {String? reason}) {
    canceled = true;
    canceledCode = code;
    canceledReason = reason;
    moveTo(KeyVerificationState.error);
  }

  Future<void> _send(String call) async {
    calls.add(call);
    await sendGate?.future;
    final error = sendError;
    if (error != null) throw error;
  }

  @override
  Future<void> continueVerification(
    String type, {
    Uint8List? qrDataRawBytes,
  }) async {
    if (qrDataRawBytes != null) scanned.add(qrDataRawBytes);
    await _send('continue($type)');
  }

  @override
  Future<void> acceptVerification() => _send('acceptVerification');

  @override
  Future<void> rejectVerification() => _send('rejectVerification');

  @override
  Future<void> acceptSas() => _send('acceptSas');

  @override
  Future<void> rejectSas() => _send('rejectSas');

  @override
  Future<void> acceptQRScanConfirmation() => _send('acceptQRScanConfirmation');

  @override
  Future<void> cancel([String code = 'm.unknown', bool quiet = false]) async {
    if (quiet) {
      calls.add('cancel($code, quiet)');
    } else {
      await _send('cancel($code)');
    }
    stopWith(code);
  }
}

class FakeDeviceKeysList extends DeviceKeysList {
  FakeDeviceKeysList(super.userId, super.client);

  Future<KeyVerification> Function()? onStart;
  int starts = 0;

  @override
  Future<KeyVerification> startVerification({
    bool? newDirectChatEnableEncryption,
    List<StateEvent>? newDirectChatInitialState,
  }) {
    starts++;
    return onStart!();
  }
}

FakeDeviceKeysList fakeDeviceKeysOf(Client client, String userId) =>
    client.userDeviceKeys[userId] = FakeDeviceKeysList(userId, client);

class FakeScannerPlatform extends MobileScannerPlatform {
  final barcodes = StreamController<BarcodeCapture?>.broadcast();
  MobileScannerException? startError;
  int starts = 0;
  int disposals = 0;

  @override
  Stream<BarcodeCapture?> get barcodesStream => barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    starts++;
    final error = startError;
    if (error != null) throw error;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(1080, 1920),
    );
  }

  @override
  Widget buildCameraView() => const SizedBox.expand();

  @override
  Future<void> stop() async {}

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> dispose() async => disposals++;

  void scan(List<BarcodeBytes?> codes) => barcodes.add(
    BarcodeCapture(
      barcodes: [for (final code in codes) Barcode(rawDecodedBytes: code)],
    ),
  );
}

BarcodeBytes decoded(List<int> bytes) =>
    DecodedBarcodeBytes(bytes: Uint8List.fromList(bytes));

FakeScannerPlatform installFakeScanner() {
  final original = MobileScannerPlatform.instance;
  final scanner = FakeScannerPlatform();
  MobileScannerPlatform.instance = scanner;
  addTearDown(() {
    MobileScannerPlatform.instance = original;
    unawaited(scanner.barcodes.close());
  });
  return scanner;
}

const permissionDenied = 0;
const permissionGranted = 1;
const permissionPermanentlyDenied = 4;

class FakeCameraPermission {
  int onRequest = permissionGranted;
  int onCheck = permissionGranted;
  bool requestThrows = false;
  Completer<void>? requestGate;
  final calls = <String>[];

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'requestPermissions':
        await requestGate?.future;
        if (requestThrows) throw PlatformException(code: 'already-running');
        return {
          for (final permission in call.arguments as List<Object?>)
            permission: onRequest,
        };
      case 'checkPermissionStatus':
        return onCheck;
      case 'openAppSettings':
        return true;
    }
    return null;
  }
}

FakeCameraPermission installFakeCameraPermission({
  int onRequest = permissionGranted,
}) {
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final permission = FakeCameraPermission()..onRequest = onRequest;
  messenger.setMockMethodCallHandler(channel, permission._handle);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return permission;
}
