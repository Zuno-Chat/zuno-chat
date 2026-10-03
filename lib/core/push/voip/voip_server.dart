import 'package:matrix/matrix.dart';

import '../zuno_push_api.dart';

sealed class VoipServerReply {
  const VoipServerReply();
}

final class VoipServerAccepted extends VoipServerReply {
  const VoipServerAccepted({required this.serverTs, this.kid});

  final int serverTs;
  final int? kid;
}

final class VoipServerUnreachable extends VoipServerReply {
  const VoipServerUnreachable({this.retryAfter});

  final Duration? retryAfter;
}

final class VoipServerRefused extends VoipServerReply {
  const VoipServerRefused({required this.status, required this.errcode});

  final int status;
  final String errcode;
}

abstract interface class VoipServer {
  Future<VoipServerReply> putVoip({
    required String appId,
    required String pushkey,
    required int kid,
    required String key,
  });

  Future<VoipServerReply> deleteVoip();

  Future<VoipServerReply> deleteDevice();
}

VoipServerReply voipServerReply<T>(
  ZunoPushResult<T> result, {
  int? Function(T value)? kidOf,
}) => switch (result) {
  ZunoPushOk(:final value, :final serverTs) => VoipServerAccepted(
    serverTs: serverTs,
    kid: kidOf?.call(value),
  ),
  ZunoPushFailure(kind: ZunoPushFailureKind.rateLimited, :final retryAfter) =>
    VoipServerUnreachable(retryAfter: retryAfter),
  ZunoPushFailure(
    kind: ZunoPushFailureKind.route ||
        ZunoPushFailureKind.network ||
        ZunoPushFailureKind.noSession ||
        ZunoPushFailureKind.unauthorized,
  ) =>
    const VoipServerUnreachable(),
  ZunoPushFailure(errcode: 'IM.ZUNO.STARTING') => const VoipServerUnreachable(),
  ZunoPushFailure(kind: ZunoPushFailureKind.unexpected, :final status?)
      when status >= 500 =>
    const VoipServerUnreachable(),
  ZunoPushFailure(:final kind, :final status, :final errcode) =>
    VoipServerRefused(status: status ?? 0, errcode: errcode ?? kind.name),
};

class ZunoPushVoipServer implements VoipServer {
  ZunoPushVoipServer(Client client)
    : this.withApi(() => ZunoPushApi.forClient(client));

  ZunoPushVoipServer.withApi(this._open);

  final ZunoPushApi Function() _open;

  @override
  Future<VoipServerReply> putVoip({
    required String appId,
    required String pushkey,
    required int kid,
    required String key,
  }) => _call(
    (api) => api.putVoip(appId: appId, pushkey: pushkey, kid: kid, key: key),
    kidOf: (acked) => acked,
  );

  @override
  Future<VoipServerReply> deleteVoip() => _call((api) => api.deleteVoip());

  @override
  Future<VoipServerReply> deleteDevice() => _call((api) => api.deleteDevice());

  Future<VoipServerReply> _call<T>(
    Future<ZunoPushResult<T>> Function(ZunoPushApi api) send, {
    int? Function(T value)? kidOf,
  }) async {
    final ZunoPushApi api;
    try {
      api = _open();
    } on StateError {
      return const VoipServerUnreachable();
    }
    try {
      return voipServerReply(await send(api), kidOf: kidOf);
    } finally {
      api.close();
    }
  }
}
