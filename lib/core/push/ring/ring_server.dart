import 'package:matrix/matrix.dart';

import '../zuno_push/zuno_push_api.dart';

sealed class RingServerReply {
  const RingServerReply();
}

final class RingServerAccepted extends RingServerReply {
  const RingServerAccepted({required this.serverTs, this.kid});

  final int serverTs;
  final int? kid;
}

final class RingServerUnreachable extends RingServerReply {
  const RingServerUnreachable({this.retryAfter});

  final Duration? retryAfter;
}

final class RingServerRefused extends RingServerReply {
  const RingServerRefused({
    required this.status,
    required this.errcode,
    this.error,
  });

  final int status;
  final String errcode;
  final String? error;
}

abstract interface class RingServer {
  Future<RingServerReply> putVoip({
    required String appId,
    required String pushkey,
    required int kid,
    required String key,
  });

  Future<RingServerReply> deleteVoip();

  Future<RingServerReply> deleteDevice();
}

RingServerReply ringServerReply<T>(
  ZunoPushResult<T> result, {
  int? Function(T value)? kidOf,
}) => switch (result) {
  ZunoPushOk(:final value, :final serverTs) => RingServerAccepted(
    serverTs: serverTs,
    kid: kidOf?.call(value),
  ),
  ZunoPushFailure(kind: ZunoPushFailureKind.rateLimited, :final retryAfter) =>
    RingServerUnreachable(retryAfter: retryAfter),
  ZunoPushFailure(
    kind: ZunoPushFailureKind.route ||
        ZunoPushFailureKind.network ||
        ZunoPushFailureKind.noSession ||
        ZunoPushFailureKind.unauthorized,
  ) =>
    const RingServerUnreachable(),
  ZunoPushFailure(errcode: 'IM.ZUNO.STARTING') => const RingServerUnreachable(),
  ZunoPushFailure(kind: ZunoPushFailureKind.unexpected, :final status?)
      when status >= 500 =>
    const RingServerUnreachable(),
  ZunoPushFailure(:final kind, :final status, :final errcode, :final error) =>
    RingServerRefused(
      status: status ?? 0,
      errcode: errcode ?? kind.name,
      error: error,
    ),
};

class ZunoPushRingServer implements RingServer {
  ZunoPushRingServer(Client client)
    : this.withApi(() => ZunoPushApi.forClient(client));

  ZunoPushRingServer.withApi(this._open);

  final ZunoPushApi Function() _open;

  @override
  Future<RingServerReply> putVoip({
    required String appId,
    required String pushkey,
    required int kid,
    required String key,
  }) => _call(
    (api) => api.putVoip(appId: appId, pushkey: pushkey, kid: kid, key: key),
    kidOf: (acked) => acked,
  );

  @override
  Future<RingServerReply> deleteVoip() => _call((api) => api.deleteVoip());

  @override
  Future<RingServerReply> deleteDevice() => _call((api) => api.deleteDevice());

  Future<RingServerReply> _call<T>(
    Future<ZunoPushResult<T>> Function(ZunoPushApi api) send, {
    int? Function(T value)? kidOf,
  }) async {
    final ZunoPushApi api;
    try {
      api = _open();
    } on StateError {
      return const RingServerUnreachable();
    }
    try {
      return ringServerReply(await send(api), kidOf: kidOf);
    } finally {
      api.close();
    }
  }
}
