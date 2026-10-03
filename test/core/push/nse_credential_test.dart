import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/push/nse_credential.dart';
import 'package:zuno/core/push/read_model/nse_app_channel.dart';
import 'package:zuno/core/push/zuno_push_api.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/nse');
  late List<MethodCall> stored;
  late SharedPreferences prefs;
  var now = DateTime(2026, 10, 2, 12);
  var mints = 0;
  ZunoPushFailure<NseCredentialGrant>? mintFailure;
  Completer<void>? mintGate;

  setUp(() async {
    now = DateTime(2026, 10, 2, 12);
    mints = 0;
    mintFailure = null;
    mintGate = null;
    stored = [];
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          stored.add(call);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  });

  NseCredentialKeeper keeper() => NseCredentialKeeper(
    mint: () async {
      mints++;
      await mintGate?.future;
      return mintFailure ??
          const ZunoPushOk(
            NseCredentialGrant(credential: 'cred', expiresTs: 1792592000000),
            serverTs: 1790000000000,
          );
    },
    channel: NseAppChannel(
      capabilities: capabilitiesLike(iosCapabilities, nseNotifications: true),
    ),
    prefs: prefs,
    now: () => now,
  );

  test('mints at sign-in and hands the credential to the extension', () async {
    expect(await keeper().ensure(allowed: true), isTrue);

    expect(stored.single.arguments, {
      'credential': 'cred',
      'expires_ts': 1792592000000,
    });
    expect(
      prefs.getInt(NseCredentialKeeper.mintedKey),
      now.millisecondsSinceEpoch,
    );
  });

  test(
    'mints again only after a day, or an hour after the extension was refused',
    () async {
      await keeper().ensure(allowed: true);
      now = now.add(const Duration(hours: 2));
      expect(await keeper().ensure(allowed: true), isFalse);
      expect(
        await keeper().ensure(allowed: true, afterAuthFailure: true),
        isTrue,
      );
      now = now.add(const Duration(minutes: 30));
      expect(
        await keeper().ensure(allowed: true, afterAuthFailure: true),
        isFalse,
      );
      now = now.add(const Duration(hours: 24));
      expect(await keeper().ensure(allowed: true), isTrue);

      expect(mints, 3);
    },
  );

  test(
    'a failed mint keeps trying on the next chance and stores nothing',
    () async {
      for (final kind in [
        ZunoPushFailureKind.network,
        ZunoPushFailureKind.route,
        ZunoPushFailureKind.rateLimited,
      ]) {
        mintFailure = ZunoPushFailure(kind);
        expect(await keeper().ensure(allowed: true), isFalse);
      }

      expect(stored, isEmpty);
      expect(prefs.getInt(NseCredentialKeeper.mintedKey), isNull);
      mintFailure = null;
      expect(await keeper().ensure(allowed: true), isTrue);
    },
  );

  test('a credential the extension could not store is minted again', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);

    expect(await keeper().ensure(allowed: true), isFalse);
    expect(prefs.getInt(NseCredentialKeeper.mintedKey), isNull);
  });

  test(
    'withdrawing notifications or choosing Nothing drops the credential',
    () async {
      await keeper().ensure(allowed: true);

      expect(await keeper().ensure(allowed: false), isFalse);

      expect(stored.last.arguments, {'credential': null, 'expires_ts': null});
      expect(prefs.getInt(NseCredentialKeeper.mintedKey), isNull);
    },
  );

  test('overlapping calls mint once and hand over one credential', () async {
    mintGate = Completer<void>();
    final shared = keeper();

    final first = shared.ensure(allowed: true);
    final second = shared.ensure(allowed: true);
    await pumpEventQueue();
    mintGate!.complete();

    expect(await first, isTrue);
    expect(await second, isFalse);
    expect(mints, 1);
    expect(stored, hasLength(1));
  });

  test(
    'choosing Nothing while the first credential is minted still drops it',
    () async {
      mintGate = Completer<void>();
      final shared = keeper();

      final minting = shared.ensure(allowed: true);
      final dropping = shared.ensure(allowed: false);
      await pumpEventQueue();
      mintGate!.complete();
      await Future.wait([minting, dropping]);

      expect(stored.last.arguments, {'credential': null, 'expires_ts': null});
      expect(prefs.getInt(NseCredentialKeeper.mintedKey), isNull);
    },
  );
}
