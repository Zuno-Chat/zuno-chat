import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/push/push_diagnostics_data.dart';
import 'package:zuno/core/push/ring_mismatch.dart';

void main() {
  final sentAt = DateTime(2026, 10, 2, 12);

  ServerHealth health({
    bool registered = true,
    int? kid = 7,
    String? result = 'sent',
    DateTime? at,
    Duration offset = Duration.zero,
  }) => ServerHealth(
    voipRegistered: registered,
    voipKid: kid,
    voipLastResult: result,
    voipLastAt: at ?? sentAt,
    serverOffset: offset,
  );

  LedgerCall call(DateTime at, {String source = 'push'}) =>
      LedgerCall(state: 'ended', source: source, at: at);

  List<RingMismatch> check(
    ServerHealth? server, {
    int? kid = 7,
    bool hasToken = true,
    List<LedgerCall>? ledger = const [],
  }) => ringMismatches(
    health: server,
    deviceKid: kid,
    deviceHasToken: hasToken,
    ledger: ledger,
  );

  test('without the server nothing can be compared', () {
    expect(check(null), isEmpty);
  });

  test('a ring the server sent and the device received matches', () {
    expect(
      check(health(), ledger: [call(sentAt.add(const Duration(seconds: 3)))]),
      isEmpty,
    );
  });

  test('a ring the server sent that never reached the device is reported at '
      'its device time', () {
    final server = health(
      at: sentAt.add(const Duration(minutes: 1)),
      offset: const Duration(minutes: 1),
    );
    expect(check(server), [
      RingMismatch(RingMismatchKind.lastRingNotReceived, at: sentAt),
    ]);
  });

  test('a call last updated long after its ring arrived still counts as '
      'received', () {
    final server = health(
      at: sentAt.add(const Duration(minutes: 1)),
      offset: const Duration(minutes: 1),
    );
    expect(
      check(server, ledger: [call(sentAt.add(const Duration(seconds: 61)))]),
      isEmpty,
    );
    expect(
      check(server, ledger: [call(sentAt.add(const Duration(minutes: 40)))]),
      isEmpty,
    );
  });

  test('a call last updated before the ring was sent does not count', () {
    expect(
      check(
        health(),
        ledger: [call(sentAt.subtract(const Duration(seconds: 6)))],
      ),
      [RingMismatch(RingMismatchKind.lastRingNotReceived, at: sentAt)],
    );
    expect(
      check(
        health(),
        ledger: [call(sentAt.subtract(const Duration(seconds: 5)))],
      ),
      isEmpty,
    );
  });

  test('a ledger that could not be read gives no verdict on the last ring', () {
    expect(check(health(), ledger: null), isEmpty);
    expect(check(health(result: 'failed'), ledger: null), [
      RingMismatch(RingMismatchKind.lastRingFailed, at: sentAt),
    ]);
  });

  test('a ring that only arrived while Zuno was open did not come by push', () {
    expect(check(health(), ledger: [call(sentAt, source: 'sync')]), [
      RingMismatch(RingMismatchKind.lastRingNotReceived, at: sentAt),
    ]);
  });

  test('a ring the server failed to send or Apple refused is reported', () {
    expect(check(health(result: 'failed')), [
      RingMismatch(RingMismatchKind.lastRingFailed, at: sentAt),
    ]);
    expect(check(health(result: 'rejected')), [
      RingMismatch(RingMismatchKind.lastRingRefused, at: sentAt),
    ]);
  });

  test(
    'a device with a call push key the server does not know is reported',
    () {
      expect(check(health(registered: false, result: null)), [
        const RingMismatch(RingMismatchKind.notRegistered),
      ]);
      expect(
        check(health(registered: false, result: null), hasToken: false),
        isEmpty,
      );
    },
  );

  test('a server key other than the device key is reported', () {
    expect(check(health(kid: 8), ledger: [call(sentAt)]), [
      const RingMismatch(RingMismatchKind.keyDiffers),
    ]);
    expect(check(health(kid: 8), kid: null, ledger: [call(sentAt)]), isEmpty);
  });
}
