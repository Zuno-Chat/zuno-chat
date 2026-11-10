import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/files/file_system.dart';
import 'package:zuno/core/matrix/database/ephemeral_to_device.dart';
import 'package:zuno/core/matrix/database/send_outbox.dart';
import 'package:zuno/core/push/nse/session_exporter.dart';

import '../../../helpers/fake_matrix.dart';

mixin _StoreBeneath on FakeDatabaseApi {
  final stored = <Uri>[];

  @override
  Future<void> storeFile(Uri mxcUri, Uint8List bytes, int time) async =>
      stored.add(mxcUri);

  @override
  Future<Uint8List?> getFile(Uri mxcUri) async => null;

  @override
  Future<void> clear() async {}

  @override
  Future<void> clearCache() async {}
}

class _Database extends FakeDatabaseApi
    with
        StoredEventsDatabase,
        RecordsRemovedEvents,
        _StoreBeneath,
        SendOutbox {}

class _NoSessionEvents extends Fake implements InboundSessionEvents {}

void main() {
  late Directory parent;
  late _Database database;
  final bytes = Uint8List.fromList([1, 2, 3]);

  Uri file(String txid) => Uri(scheme: 'cache', host: 'file', path: txid);
  Uri thumbnail(String txid) =>
      Uri(scheme: 'cache', host: 'thumbnail', path: txid);

  int filesOnDisk() =>
      parent.listSync(recursive: true).whereType<File>().length;

  setUp(() async {
    parent = await fileSystem.systemTempDirectory.createTemp('outbox_test');
    sendOutboxParent = () async => parent;
    addTearDown(() => parent.delete(recursive: true));
    database = _Database();
  });

  test('keeps an unsent file on disk until the SDK lets go once it is '
      'sent', () async {
    await database.storeFile(file('txn1'), bytes, 0);

    expect(await database.getFile(file('txn1')), bytes);
    expect(filesOnDisk(), 1);

    await database.deleteFile(file('txn1'));

    expect(await database.getFile(file('txn1')), isNull);
    expect(filesOnDisk(), 0);
  });

  test('an unsent file is still there after a restart', () async {
    await database.storeFile(file('txn1'), bytes, 0);

    expect(await _Database().getFile(file('txn1')), bytes);
  });

  test('deletes a file and its thumbnail once their message is removed, '
      'sent or deleted', () async {
    await database.storeFile(file('txn1'), bytes, 0);
    await database.storeFile(thumbnail('txn1'), bytes, 0);
    await database.storeFile(file('txn2'), bytes, 0);

    await database.removeEvent('txn1', '!room:example.org');

    expect(database.removed, ['txn1']);
    expect(await database.getFile(file('txn1')), isNull);
    expect(await database.getFile(thumbnail('txn1')), isNull);
    expect(await database.getFile(file('txn2')), bytes);
    expect(filesOnDisk(), 1);
  });

  test('deletes everything on sign-out', () async {
    await database.storeFile(file('txn1'), bytes, 0);

    await database.clear();

    expect(filesOnDisk(), 0);
  });

  test('deletes everything when the cache is cleared, since unsent messages '
      'go with it', () async {
    await database.storeFile(file('txn1'), bytes, 0);

    await database.clearCache();

    expect(filesOnDisk(), 0);
  });

  test('leaves downloaded media to the store beneath', () async {
    final media = Uri.parse('mxc://example.org/media');

    await database.storeFile(media, bytes, 0);

    expect(database.stored, [media]);
    expect(await database.getFile(media), isNull);
    expect(filesOnDisk(), 0);
  });

  test('a file that cannot be written never stops the send', () async {
    await parent.childFile('send_outbox').create();

    await database.storeFile(file('txn1'), bytes, 0);

    expect(await database.getFile(file('txn1')), isNull);
  });

  test('at launch, drops files whose message is gone and keeps those still '
      'waiting to be sent and those written since', () async {
    final earlierRun = _Database();
    await earlierRun.storeFile(file('txn-waiting'), bytes, 0);
    await earlierRun.storeFile(file('txn-gone'), bytes, 0);
    await earlierRun.storeFile(thumbnail('txn-gone'), bytes, 0);
    final client = buildTestClient(userId: '@me:x', database: database);
    final room = buildTestRoom(client);
    client.rooms.add(room);
    database.events = [
      buildTestEvent(
        room,
        eventId: 'txn-waiting',
        senderId: '@me:x',
        status: EventStatus.error,
        content: {'msgtype': MessageTypes.Audio, 'body': 'Voice message.ogg'},
      ),
    ];
    await database.storeFile(file('txn-new'), bytes, 0);

    await dropSendOutboxOrphans(client);

    expect(await database.getFile(file('txn-waiting')), bytes);
    expect(await database.getFile(file('txn-new')), bytes);
    expect(await database.getFile(file('txn-gone')), isNull);
    expect(filesOnDisk(), 2);
  });

  group("the app's databases keep unsent files for the SDK", () {
    for (final (name, build) in [
      ('ZunoDatabase', () => ZunoDatabase('test')),
      (
        'SessionExportingDatabase',
        () => SessionExportingDatabase(
          'test',
          inboundSessionEvents: _NoSessionEvents(),
        ),
      ),
    ]) {
      test(name, () async {
        final appDatabase = build();

        await appDatabase.storeFile(file('txn1'), bytes, 0);

        expect(await appDatabase.getFile(file('txn1')), bytes);
      });
    }
  });
}
