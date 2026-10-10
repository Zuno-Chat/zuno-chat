import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/push/pusher_removal.dart';

import '../../helpers/pusher_recording_client.dart';

void main() {
  late PusherRecordingClient client;
  final pusher = PusherId(appId: 'im.zuno.chat.android', pushkey: 'token-abc');

  setUp(() => client = PusherRecordingClient());

  test('removes the pusher of a session that is still signed in', () async {
    await removePusher(client, pusher);

    expect(client.deleted.single.pushkey, 'token-abc');
    expect(client.deleted.single.appId, 'im.zuno.chat.android');
  });

  test('asks nothing once the session has ended, since the homeserver '
      'dropped its pushers with it', () async {
    client.signedIn = false;

    await removePusher(client, pusher);

    expect(client.deleted, isEmpty);
  });

  for (final errcode in ['M_UNKNOWN_TOKEN', 'M_MISSING_TOKEN']) {
    test('treats $errcode as a pusher already gone', () async {
      client.deleteError = MatrixException.fromJson({'errcode': errcode});

      await expectLater(removePusher(client, pusher), completes);
    });
  }

  test('passes any other refusal on', () async {
    client.deleteError = MatrixException.fromJson({'errcode': 'M_FORBIDDEN'});

    await expectLater(
      removePusher(client, pusher),
      throwsA(
        isA<MatrixException>().having(
          (e) => e.errcode,
          'errcode',
          'M_FORBIDDEN',
        ),
      ),
    );
  });

  test('passes a failure that is not the server\'s answer on', () async {
    client.deleteError = StateError('connection reset');

    await expectLater(removePusher(client, pusher), throwsStateError);
  });
}
