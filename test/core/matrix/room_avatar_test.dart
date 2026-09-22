import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/room_avatar.dart';

import '../../helpers/fake_matrix.dart';

class _UploadCapableFakeDatabaseApi extends FakeDatabaseApi {
  @override
  int get maxFileSize => 0;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) async {}

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async => null;
}

void main() {
  late List<http.Request> requests;
  late Room room;

  setUp(() {
    requests = [];
    final client = Client(
      'test',
      database: _UploadCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        if (request.url.pathSegments.last == 'config') {
          return http.Response('{}', 200);
        }
        if (request.url.pathSegments.last == 'versions') {
          return http.Response(
            jsonEncode({
              'versions': ['v1.11'],
            }),
            200,
          );
        }
        requests.add(request);
        if (request.url.pathSegments.contains('upload')) {
          return http.Response(
            jsonEncode({'content_uri': 'mxc://example.org/new'}),
            200,
          );
        }
        return http.Response(jsonEncode({'event_id': r'$evt'}), 200);
      }),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
  });

  test('uploads, sets the state and shows the new avatar at once', () async {
    await setRoomAvatar(
      room,
      MatrixFile(bytes: Uint8List.fromList([1, 2, 3]), name: 'a.png'),
    );

    expect(requests, hasLength(2));
    expect(requests[0].url.pathSegments, contains('upload'));
    expect(requests[1].url.pathSegments, contains('m.room.avatar'));
    expect(jsonDecode(requests[1].body), {'url': 'mxc://example.org/new'});
    expect(room.avatar.toString(), 'mxc://example.org/new');
  });

  test('removing clears the state and the avatar at once', () async {
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$avatar',
        senderId: '@me:example.org',
        type: EventTypes.RoomAvatar,
        stateKey: '',
        content: {'url': 'mxc://example.org/old'},
      ),
    );

    await setRoomAvatar(room, null);

    expect(requests, hasLength(1));
    expect(requests.single.url.pathSegments, contains('m.room.avatar'));
    expect(jsonDecode(requests.single.body), <String, Object?>{});
    expect(room.avatar, isNull);
  });
}
