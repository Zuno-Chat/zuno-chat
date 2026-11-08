import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../errors/best_effort.dart';

typedef _SenderCryptor = ({RTCRtpSender sender, FrameCryptor cryptor});

typedef _ReceiverCryptor = ({RTCRtpReceiver receiver, FrameCryptor cryptor});

class CallEncryptionCheckpoint {
  CallEncryptionCheckpoint._(this._senders, this._hadKey);

  final Map<String, _SenderCryptor> _senders;
  final bool _hadKey;
}

class CallEncryption {
  CallEncryption(this._factory, {required this._onSendersChanged});

  final FrameCryptorFactory _factory;
  final void Function() _onSendersChanged;

  KeyProvider? _provider;
  final Map<String, _SenderCryptor> _senders = {};
  final Set<RTCRtpSender> _senderWrapsInFlight = Set.identity();
  final Map<String, _ReceiverCryptor> _receivers = {};
  final Set<String> _receiverWrapsInFlight = {};

  bool get hasKey => _provider != null;

  Future<void> setKey(Uint8List key) async {
    final existing = _provider;
    final provider =
        existing ??
        await _factory.createDefaultKeyProvider(
          KeyProviderOptions(
            sharedKey: true,
            ratchetSalt: Uint8List.fromList('zuno.calls.e2ee'.codeUnits),
            ratchetWindowSize: 0,
          ),
        );
    try {
      await provider.setSharedKey(key: key);
    } catch (_) {
      if (existing == null) {
        await runBestEffort(
          provider.dispose,
          label: 'dispose a key provider that refused the key',
        );
      }
      rethrow;
    }
    _provider = provider;
  }

  CallEncryptionCheckpoint checkpoint() =>
      CallEncryptionCheckpoint._(Map.of(_senders), hasKey);

  Future<void> rollBack(CallEncryptionCheckpoint checkpoint) async {
    final dropped = [
      for (final label in [
        for (final MapEntry(key: label, value: wrapped) in _senders.entries)
          if (!identical(checkpoint._senders[label], wrapped)) label,
      ])
        _senders.remove(label)!.cryptor,
    ];
    if (dropped.isNotEmpty) _onSendersChanged();
    await _disposeCryptors(dropped, 'after a key that could not be applied');
    if (checkpoint._hadKey) return;
    final receivers = [
      for (final wrapped in _receivers.values) wrapped.cryptor,
    ];
    _receivers.clear();
    await _disposeCryptors(
      receivers,
      'made with a key that could not be applied',
    );
    await _disposeProvider('after a key that could not be applied');
  }

  Future<bool> wrapSender(
    String label,
    RTCRtpSender sender, {
    required bool Function() stillWanted,
  }) => _wrap(
    usable: sender.track != null,
    wrapped: identical(_senders[label]?.sender, sender),
    inFlight: _senderWrapsInFlight,
    key: sender,
    stillWanted: stillWanted,
    create: (provider) => _factory.createFrameCryptorForRtpSender(
      participantId: label,
      sender: sender,
      algorithm: Algorithm.kAesGcm,
      keyProvider: provider,
    ),
    unwanted: 'for a sender no longer in use',
    side: 'sender',
    keep: (cryptor) {
      final replaced = _senders[label];
      _senders[label] = (sender: sender, cryptor: cryptor);
      _onSendersChanged();
      return replaced?.cryptor;
    },
  );

  bool encrypts(String label, RTCRtpSender? current) =>
      current != null && identical(_senders[label]?.sender, current);

  Future<bool> wrapReceiver(
    String label,
    RTCRtpReceiver receiver, {
    required bool Function() stillWanted,
  }) => _wrap(
    usable: stillWanted(),
    wrapped: decrypts(label, receiver),
    inFlight: _receiverWrapsInFlight,
    key: receiver.receiverId,
    stillWanted: stillWanted,
    create: (provider) => _factory.createFrameCryptorForRtpReceiver(
      participantId: label,
      receiver: receiver,
      algorithm: Algorithm.kAesGcm,
      keyProvider: provider,
    ),
    unwanted: 'for a closed connection',
    side: 'receiver',
    keep: (cryptor) {
      final replaced = _receivers[label];
      _receivers[label] = (receiver: receiver, cryptor: cryptor);
      return replaced?.cryptor;
    },
  );

  Future<bool> _wrap<K extends Object>({
    required bool usable,
    required bool wrapped,
    required Set<K> inFlight,
    required K key,
    required bool Function() stillWanted,
    required Future<FrameCryptor> Function(KeyProvider provider) create,
    required String unwanted,
    required String side,
    required FrameCryptor? Function(FrameCryptor cryptor) keep,
  }) async {
    final provider = _provider;
    if (provider == null || !usable) return false;
    if (wrapped) return true;
    if (!inFlight.add(key)) return false;
    bool wanted() => stillWanted() && identical(_provider, provider);
    try {
      final FrameCryptor cryptor;
      try {
        cryptor = await create(provider);
      } catch (_) {
        if (wanted()) rethrow;
        return false;
      }
      if (wanted()) {
        try {
          await cryptor.setEnabled(true);
        } catch (_) {
          await _disposeCryptors([cryptor], 'that failed to start');
          if (wanted()) rethrow;
          return false;
        }
      }
      if (!wanted()) {
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

  Future<void> dispose() async {
    await forgetAll();
    await _disposeProvider('on leave');
  }

  Future<void> _disposeProvider(String reason) async {
    final provider = _provider;
    if (provider == null) return;
    _provider = null;
    await runBestEffort(
      provider.dispose,
      label: 'dispose key provider $reason',
    );
  }

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
