import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/cloudflare/remote_track_plan.dart';

void main() {
  const both = ['audio', 'video'];

  List<String> plan({
    Iterable<String> advertised = both,
    Set<String> pulled = const {},
    bool remoteVideoEnabled = true,
    bool remoteEncrypted = true,
    bool localEncrypted = true,
  }) => planRemoteTracks(
    advertised: advertised,
    pulled: pulled,
    remoteVideoEnabled: remoteVideoEnabled,
    remoteEncrypted: remoteEncrypted,
    localEncrypted: localEncrypted,
  );

  group('happy path', () {
    test('pulls every advertised track when both sides are keyed', () {
      expect(plan(), ['audio', 'video']);
    });

    test('skips already pulled tracks', () {
      expect(plan(pulled: {'audio'}), ['video']);
    });

    test('keeps a pulled video when the remote camera turns off', () {
      expect(
        plan(pulled: {'audio', 'video'}, remoteVideoEnabled: false),
        isEmpty,
      );
    });

    test('pulls video once the remote camera turns on', () {
      expect(plan(pulled: {'audio'}, remoteVideoEnabled: true), ['video']);
    });
  });

  group('sad paths', () {
    test('pulls nothing while the remote is encrypted and we have no key', () {
      expect(plan(localEncrypted: false), isEmpty);
    });

    test('two unkeyed peers pull nothing from each other', () {
      expect(plan(remoteEncrypted: false, localEncrypted: false), isEmpty);
    });

    test('pulls nothing while we hold a key and the remote does not', () {
      expect(plan(remoteEncrypted: false), isEmpty);
    });

    test('does not pull video while the remote camera is off', () {
      expect(plan(remoteVideoEnabled: false), ['audio']);
    });

    test('unknown advertised track names are never pulled', () {
      expect(plan(advertised: ['audio', 'video', 'screen', 'foo']), [
        'audio',
        'video',
      ]);
    });
  });
}
