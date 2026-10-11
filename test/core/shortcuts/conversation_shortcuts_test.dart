import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/shortcuts/conversation_shortcuts.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late RecordedMethodCalls native;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    client.rooms.addAll([
      Room(id: '!joined:example.org', client: client),
      Room(
        id: '!invited:example.org',
        membership: Membership.invite,
        client: client,
      ),
      Room(
        id: '!asked:example.org',
        membership: Membership.knock,
        client: client,
      ),
    ]);
    native = recordMethodChannel('zuno/conversations');
  });

  void watch(PlatformCapabilities capabilities) {
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        platformCapabilitiesProvider.overrideWithValue(capabilities),
      ],
    );
    addTearDown(container.dispose);
    container.listen(conversationShortcutsProvider, (_, _) {});
  }

  Future<void> sync({Map<String, LeftRoomUpdate>? leave}) async {
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'batch',
        rooms: leave == null ? null : RoomsUpdate(leave: leave),
      ),
    );
    await pumpEventQueue();
  }

  List<Object?> retained() => [
    for (final args in native.argsOf('retainConversationShortcuts'))
      (args! as Map)['roomIds'],
  ];

  test('the first sync keeps shortcuts only for rooms you are in', () async {
    watch(androidCapabilities);

    await sync();

    expect(retained(), [
      ['!joined:example.org', '!invited:example.org'],
    ]);
  });

  test('a room you leave or are removed from loses its shortcut', () async {
    watch(androidCapabilities);
    await sync();

    client.rooms.removeWhere((room) => room.id == '!joined:example.org');
    await sync(leave: {'!joined:example.org': LeftRoomUpdate()});

    expect(retained().last, ['!invited:example.org']);
  });

  test('a sync that leaves no room asks nothing of native', () async {
    watch(androidCapabilities);
    await sync();

    await sync();
    await sync(leave: {});

    expect(retained(), hasLength(1));
  });

  test('a platform without home screen shortcuts never calls native', () async {
    watch(iosCapabilities);

    await sync();
    await sync(leave: {'!joined:example.org': LeftRoomUpdate()});

    expect(native.calls, isEmpty);
  });
}
