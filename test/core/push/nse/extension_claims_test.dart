import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/nse/extension_claims.dart';
import 'package:zuno/core/push/nse/nse_app_channel.dart';

import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/nse');
  final ios = capabilitiesLike(iosCapabilities, nseNotifications: true);
  late Set<String> held;
  late List<List<Object?>> asked;
  Completer<void>? hold;
  late ExtensionClaims claims;

  setUp(() {
    held = {};
    asked = [];
    hold = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'shownByExtension') return null;
          final sent = (call.arguments as Map)['claims'] as List<Object?>;
          asked.add(sent);
          final answer = [
            for (final claim in sent) held.contains((claim! as Map)['id']),
          ];
          await hold?.future;
          return answer;
        });
    claims = ExtensionClaims(NseAppChannel(capabilities: ios));
    addTearDown(() {
      claims.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });

  Future<void> alertHidden() async {
    await callFromNative(channel, 'alertHiddenInFront');
    await pumpEventQueue();
  }

  test('defers only to an alert the extension still holds', () async {
    held = {r'$shown'};

    expect(
      await claims.deferredToExtension(
        const ExtensionClaim.event(r'$shown'),
        retry: () async {},
      ),
      isTrue,
    );
    expect(
      await claims.deferredToExtension(
        const ExtensionClaim.event(r'$new'),
        retry: () async {},
      ),
      isFalse,
    );
  });

  test('once an alert is hidden in front, asks about every parked claim in '
      'one call and retries only those released', () async {
    held = {r'$a', '!r:x', r'$b'};
    final retried = <String>[];
    for (final (claim, name) in [
      (const ExtensionClaim.event(r'$a'), 'a'),
      (const ExtensionClaim.invite('!r:x'), 'invite'),
      (const ExtensionClaim.event(r'$b'), 'b'),
    ]) {
      await claims.deferredToExtension(
        claim,
        retry: () async => retried.add(name),
      );
    }
    asked.clear();

    held = {r'$b'};
    await alertHidden();

    expect(asked, hasLength(1));
    expect(asked.single, hasLength(3));
    expect(retried, unorderedEquals(['a', 'invite']));

    retried.clear();
    held = {};
    await alertHidden();
    expect(retried, ['b']);
  });

  test('an alert hidden while its claim is still being asked about is '
      'retried once the claim parks', () async {
    held = {r'$x'};
    final answered = Completer<void>();
    hold = answered;
    var retried = false;
    final deferred = claims.deferredToExtension(
      const ExtensionClaim.event(r'$x'),
      retry: () async => retried = true,
    );
    await pumpEventQueue();
    hold = null;
    held = {};

    await alertHidden();
    answered.complete();

    expect(await deferred, isTrue);
    await pumpEventQueue();
    expect(retried, isTrue);
  });

  test('a hidden alert with nothing parked asks nothing', () async {
    await alertHidden();

    expect(asked, isEmpty);
  });

  test('keeps only the newest parked claims', () async {
    held = {for (var i = 0; i <= maxParkedClaims; i++) '\$$i'};
    final retried = <int>[];
    for (var i = 0; i <= maxParkedClaims; i++) {
      await claims.deferredToExtension(
        ExtensionClaim.event('\$$i'),
        retry: () async => retried.add(i),
      );
    }

    held = {};
    await alertHidden();

    expect(retried, hasLength(maxParkedClaims));
    expect(retried, isNot(contains(0)));
  });

  test('a failed retry leaves the others to run', () async {
    held = {r'$a', r'$b'};
    final retried = <String>[];
    await claims.deferredToExtension(
      const ExtensionClaim.event(r'$a'),
      retry: () async => throw StateError('boom'),
    );
    await claims.deferredToExtension(
      const ExtensionClaim.event(r'$b'),
      retry: () async => retried.add('b'),
    );

    held = {};
    await alertHidden();

    expect(retried, ['b']);
  });

  test('once disposed, a hidden alert retries nothing', () async {
    held = {r'$a'};
    var retried = false;
    await claims.deferredToExtension(
      const ExtensionClaim.event(r'$a'),
      retry: () async => retried = true,
    );

    claims.dispose();
    held = {};
    await alertHidden();

    expect(retried, isFalse);
  });

  test('without the extension nothing is deferred or asked', () async {
    final android = ExtensionClaims(
      NseAppChannel(capabilities: androidCapabilities),
    );
    addTearDown(android.dispose);

    expect(
      await android.deferredToExtension(
        const ExtensionClaim.event(r'$a'),
        retry: () async {},
      ),
      isFalse,
    );
    expect(asked, isEmpty);
  });
}
