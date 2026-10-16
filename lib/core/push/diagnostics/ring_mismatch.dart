import 'package:flutter/foundation.dart' show immutable;

import 'push_diagnostics_data.dart';

enum RingMismatchKind {
  notRegistered,
  keyDiffers,
  lastRingNotReceived,
  lastRingFailed,
  lastRingRefused,
}

@immutable
class RingMismatch {
  const RingMismatch(this.kind, {this.at});

  final RingMismatchKind kind;
  final DateTime? at;

  @override
  bool operator ==(Object other) =>
      other is RingMismatch && other.kind == kind && other.at == at;

  @override
  int get hashCode => Object.hash(kind, at);

  @override
  String toString() => 'RingMismatch(${kind.name}, $at)';
}

const ringArrivalWindowBefore = Duration(seconds: 5);

List<RingMismatch> ringMismatches({
  required ServerHealth? health,
  required int? deviceKid,
  required bool deviceHasToken,
  required List<LedgerCall>? ledger,
}) {
  if (health == null) return const [];
  final found = <RingMismatch>[];
  if (deviceHasToken && !health.voipRegistered) {
    found.add(const RingMismatch(RingMismatchKind.notRegistered));
  }
  final serverKid = health.voipKid;
  if (health.voipRegistered &&
      deviceKid != null &&
      serverKid != null &&
      serverKid != deviceKid) {
    found.add(const RingMismatch(RingMismatchKind.keyDiffers));
  }
  final lastAt = health.voipLastAt;
  if (lastAt == null) return found;
  final at = health.toDevice(lastAt);
  switch (health.voipLastResult) {
    case 'failed':
      found.add(RingMismatch(RingMismatchKind.lastRingFailed, at: at));
    case 'rejected':
      found.add(RingMismatch(RingMismatchKind.lastRingRefused, at: at));
    case 'sent':
      final from = at.subtract(ringArrivalWindowBefore);
      final arrived = ledger?.any(
        (call) => call.source == 'push' && !call.at.isBefore(from),
      );
      if (arrived == false) {
        found.add(RingMismatch(RingMismatchKind.lastRingNotReceived, at: at));
      }
  }
  return found;
}
