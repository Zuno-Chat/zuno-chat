import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/left_rooms_repair.dart';

import '../../helpers/fake_matrix.dart';

class _RepairClient extends Client {
  _RepairClient({required this.loggedIn})
    : super('test', database: FakeDatabaseApi());

  final bool loggedIn;
  var clears = 0;
  Object? clearFailure;
  Completer<void>? finishing;

  @override
  bool isLogged() => loggedIn;

  @override
  Future<void> clearCache() async {
    clears++;
    if (clearFailure case final failure?) throw failure;
    await finishing?.future;
  }
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('a signed-in store from before this release is rebuilt once', () async {
    final client = _RepairClient(loggedIn: true);

    await repairLeftRoomsOnce(client, prefs);
    await repairLeftRoomsOnce(client, prefs);

    expect(client.clears, 1);
  });

  test('a store with no session is never rebuilt', () async {
    await repairLeftRoomsOnce(_RepairClient(loggedIn: false), prefs);
    final signedInLater = _RepairClient(loggedIn: true);

    await repairLeftRoomsOnce(signedInLater, prefs);

    expect(signedInLater.clears, 0);
  });

  test('a rebuild that fails is tried again on the next start', () async {
    final client = _RepairClient(loggedIn: true)
      ..clearFailure = StateError('database locked');

    await repairLeftRoomsOnce(client, prefs);
    client.clearFailure = null;
    await repairLeftRoomsOnce(client, prefs);
    await repairLeftRoomsOnce(client, prefs);

    expect(client.clears, 2);
  });

  test('the rebuild counts as done only once its clear, space given back '
      'included, has finished', () async {
    final client = _RepairClient(loggedIn: true);
    final finishing = client.finishing = Completer();

    final repair = repairLeftRoomsOnce(client, prefs);
    await pumpEventQueue();

    expect(client.clears, 1);
    expect(prefs.getBool(leftRoomsRepairedKey), isNull);

    finishing.complete();
    await repair;

    expect(prefs.getBool(leftRoomsRepairedKey), isTrue);
  });
}
