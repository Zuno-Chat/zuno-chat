import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/cloudflare/remote_track_plan.dart';
import 'package:zuno/core/calls/media/call_connection.dart';

void main() {
  const both = ['audio', 'video'];

  List<String> plan({
    Iterable<String> advertised = both,
    Set<String> pulled = const {},
    Set<MediaKind> wanted = const {MediaKind.audio, MediaKind.video},
  }) =>
      planRemoteTracks(advertised: advertised, pulled: pulled, wanted: wanted);

  group('happy path', () {
    test('pulls every advertised track that is wanted', () {
      expect(plan(), ['audio', 'video']);
    });

    test('skips already pulled tracks', () {
      expect(plan(pulled: {'audio'}), ['video']);
    });

    test('keeps a pulled video once video is no longer wanted', () {
      expect(
        plan(pulled: {'audio', 'video'}, wanted: {MediaKind.audio}),
        isEmpty,
      );
    });
  });

  group('sad paths', () {
    test('pulls nothing while nothing is wanted', () {
      expect(plan(wanted: const {}), isEmpty);
    });

    test('does not pull video unless it is wanted', () {
      expect(plan(wanted: {MediaKind.audio}), ['audio']);
    });

    test('a wanted track that is not advertised is never pulled', () {
      expect(plan(advertised: ['audio']), ['audio']);
    });

    test('unknown advertised track names are never pulled', () {
      expect(plan(advertised: ['audio', 'video', 'screen', 'foo']), [
        'audio',
        'video',
      ]);
    });
  });
}
