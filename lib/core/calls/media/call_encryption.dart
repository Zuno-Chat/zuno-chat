import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../async/serial_lock.dart';
import '../../errors/best_effort.dart';
import '../models/voip_participant_id.dart';
import 'call_key_slots.dart';

typedef _SenderCryptor = ({
  RTCRtpSender sender,
  FrameCryptor cryptor,
  int slot,
});

typedef _ReceiverCryptor = ({
  VoipParticipantId id,
  RTCRtpReceiver receiver,
  FrameCryptor cryptor,
});

final class _Keys {
  _Keys(this.provider);

  final KeyProvider provider;
  final Set<int> slots = {};
}

class CallEncryption {
  CallEncryption(this._factory, {required this._onSendersChanged});

  final FrameCryptorFactory _factory;
  final void Function() _onSendersChanged;

  _Keys? _own;
  final Map<VoipParticipantId, _Keys> _peers = {};
  int? _sendSlot;
  bool _disposed = false;
  final Map<String, _SenderCryptor> _senders = {};
  final Set<RTCRtpSender> _senderWrapsInFlight = Set.identity();
  final Map<String, _ReceiverCryptor> _receivers = {};
  final Set<String> _receiverWrapsInFlight = {};
  final _lock = SerialLock();

  bool get canSend {
    final slot = _sendSlot;
    return slot != null && (_own?.slots.contains(slot) ?? false);
  }

  bool holdsKeyFor(VoipParticipantId id) =>
      _peers[id]?.slots.isNotEmpty ?? false;

  Future<void> _change(Future<void> Function() change) => _lock.run(() async {
    if (!_disposed) await change();
  });

  Future<void> setOwnKey(int slot, Uint8List key) => _change(() async {
    final fresh = _own == null;
    final keys = _own ??= await _create();
    await _setKey(keys, slot, key, discard: fresh ? () => _own = null : null);
  });

  Future<void> setPeerKey(VoipParticipantId id, int slot, Uint8List key) =>
      _change(() async {
        final fresh = !_peers.containsKey(id);
        final keys = _peers[id] ??= await _create();
        await _setKey(
          keys,
          slot,
          key,
          discard: fresh ? () => _peers.remove(id) : null,
        );
      });

  Future<void> sendWithSlot(int slot) => _change(() async {
    if (!(_own?.slots.contains(slot) ?? false)) {
      throw StateError('Our key provider holds no key in slot $slot');
    }
    _sendSlot = slot;
    await Future.wait([
      for (final label in _senders.keys.toList()) _point(label),
    ]);
  });

  Future<void> forgetPeer(VoipParticipantId id) => _change(() async {
    final keys = _peers.remove(id);
    final cryptors = [
      for (final label in [
        for (final MapEntry(key: label, value: wrapped) in _receivers.entries)
          if (wrapped.id == id) label,
      ])
        _receivers.remove(label)!.cryptor,
    ];
    await _disposeCryptors(cryptors, 'of a forgotten participant');
    if (keys != null) {
      await _disposeProvider(keys, 'of a forgotten participant');
    }
  });

  Future<_Keys> _create() async => _Keys(
    await _factory.createDefaultKeyProvider(
      KeyProviderOptions(
        sharedKey: true,
        ratchetSalt: Uint8List.fromList('LKFrameEncryptionKey'.codeUnits),
        ratchetWindowSize: 0,
        keyRingSize: keyRingSize,
        keyDerivationAlgorithm: KeyDerivationAlgorithm.kHKDF,
      ),
    ),
  );

  Future<void> _setKey(
    _Keys keys,
    int slot,
    Uint8List key, {
    void Function()? discard,
  }) async {
    try {
      await keys.provider.setSharedKey(key: key, index: slot);
    } catch (_) {
      if (discard != null) {
        discard();
        await _disposeProvider(keys, 'that refused a key');
      }
      rethrow;
    }
    keys.slots.add(slot);
  }

  Future<void> _point(String label) async {
    final wrapped = _senders[label];
    final slot = _sendSlot;
    if (wrapped == null || slot == null || wrapped.slot == slot) return;
    await wrapped.cryptor.setKeyIndex(slot);
    if (identical(_senders[label]?.cryptor, wrapped.cryptor)) {
      _senders[label] = (
        sender: wrapped.sender,
        cryptor: wrapped.cryptor,
        slot: slot,
      );
    }
  }

  Future<bool> wrapSender(
    String label,
    RTCRtpSender sender, {
    required bool Function() stillWanted,
  }) async {
    final own = _own;
    if (own == null || !canSend) return false;
    var slot = _sendSlot!;
    final wrapped = await _wrap(
      usable: sender.track != null,
      wrapped: identical(_senders[label]?.sender, sender),
      inFlight: _senderWrapsInFlight,
      key: sender,
      stillWanted: () => stillWanted() && identical(_own, own),
      create: () async {
        final cryptor = await _factory.createFrameCryptorForRtpSender(
          participantId: label,
          sender: sender,
          algorithm: Algorithm.kAesGcm,
          keyProvider: own.provider,
        );
        slot = _sendSlot ?? slot;
        try {
          await cryptor.setKeyIndex(slot);
        } catch (_) {
          await _disposeCryptors([cryptor], 'that could not take its key slot');
          rethrow;
        }
        return cryptor;
      },
      unwanted: 'for a sender no longer in use',
      side: 'sender',
      keep: (cryptor) {
        final replaced = _senders[label];
        _senders[label] = (sender: sender, cryptor: cryptor, slot: slot);
        _onSendersChanged();
        return replaced?.cryptor;
      },
    );
    if (wrapped) await _point(label);
    return wrapped;
  }

  bool encrypts(String label, RTCRtpSender? current) =>
      current != null && identical(_senders[label]?.sender, current);

  Future<bool> wrapReceiver(
    VoipParticipantId id,
    String label,
    RTCRtpReceiver receiver, {
    required bool Function() stillWanted,
  }) async {
    final keys = _peers[id];
    if (keys == null || keys.slots.isEmpty) return false;
    return _wrap(
      usable: stillWanted(),
      wrapped: decrypts(label, receiver),
      inFlight: _receiverWrapsInFlight,
      key: receiver.receiverId,
      stillWanted: () => stillWanted() && identical(_peers[id], keys),
      create: () => _factory.createFrameCryptorForRtpReceiver(
        participantId: label,
        receiver: receiver,
        algorithm: Algorithm.kAesGcm,
        keyProvider: keys.provider,
      ),
      unwanted: 'for a closed connection',
      side: 'receiver',
      keep: (cryptor) {
        final replaced = _receivers[label];
        _receivers[label] = (id: id, receiver: receiver, cryptor: cryptor);
        return replaced?.cryptor;
      },
    );
  }

  Future<bool> _wrap<K extends Object>({
    required bool usable,
    required bool wrapped,
    required Set<K> inFlight,
    required K key,
    required bool Function() stillWanted,
    required Future<FrameCryptor> Function() create,
    required String unwanted,
    required String side,
    required FrameCryptor? Function(FrameCryptor cryptor) keep,
  }) async {
    if (!usable) return false;
    if (wrapped) return true;
    if (!inFlight.add(key)) return false;
    try {
      final FrameCryptor cryptor;
      try {
        cryptor = await create();
      } catch (_) {
        if (stillWanted()) rethrow;
        return false;
      }
      if (stillWanted()) {
        try {
          await cryptor.setEnabled(true);
        } catch (_) {
          await _disposeCryptors([cryptor], 'that failed to start');
          if (stillWanted()) rethrow;
          return false;
        }
      }
      if (!stillWanted()) {
        await _disposeCryptors([cryptor], unwanted);
        return false;
      }
      if (keep(cryptor) case final replaced?) {
        await _disposeCryptors([replaced], 'for a replaced $side');
      }
      return true;
    } finally {
      inFlight.remove(key);
    }
  }

  bool decrypts(String label, RTCRtpReceiver? receiver) =>
      receiver != null &&
      _receivers[label]?.receiver.receiverId == receiver.receiverId;

  Future<void> dropReceiver(String label) async {
    final wrapped = _receivers.remove(label);
    if (wrapped != null) await _disposeCryptors([wrapped.cryptor], 'on close');
  }

  Future<void> forgetAll() async {
    final cryptors = [
      for (final wrapped in _senders.values) wrapped.cryptor,
      for (final wrapped in _receivers.values) wrapped.cryptor,
    ];
    _senders.clear();
    _receivers.clear();
    _onSendersChanged();
    await _disposeCryptors(cryptors, 'on teardown');
  }

  Future<void> dispose() {
    _disposed = true;
    return _lock.run(() async {
      final providers = [?_own, ..._peers.values];
      _own = null;
      _peers.clear();
      _sendSlot = null;
      await forgetAll();
      for (final keys in providers) {
        await _disposeProvider(keys, 'on leave');
      }
    });
  }

  Future<void> _disposeProvider(_Keys keys, String reason) => runBestEffort(
    keys.provider.dispose,
    label: 'dispose key provider $reason',
  );

  Future<void> _disposeCryptors(
    Iterable<FrameCryptor> cryptors,
    String reason,
  ) async {
    await Future.wait([
      for (final cryptor in cryptors)
        runBestEffort(cryptor.dispose, label: 'dispose cryptor $reason'),
    ]);
  }
}
