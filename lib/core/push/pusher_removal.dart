import 'package:matrix/matrix.dart';

const _sessionGone = {'M_UNKNOWN_TOKEN', 'M_MISSING_TOKEN'};

Future<void> removePusher(Client client, PusherId id) async {
  if (!client.isLogged()) return;
  try {
    await client.deletePusher(id);
  } on MatrixException catch (e) {
    if (!_sessionGone.contains(e.errcode)) rethrow;
  }
}
