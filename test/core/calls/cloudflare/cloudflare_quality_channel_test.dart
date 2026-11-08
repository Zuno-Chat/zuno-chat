import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/cloudflare/cloudflare_quality_channel.dart';

import '../../../helpers/call_fixtures.dart';

void main() {
  test('one claim per peer session until it is released', () {
    final channel = CloudflareQualityChannel(onRating: (_, _) {});

    final claim = channel.claim(ann, 'remote-1')!;

    expect(channel.claim(ann, 'remote-1'), isNull);
    channel.release(ann, claim);
    expect(channel.claim(ann, 'remote-1'), isNotNull);
  });

  test(
    'a release from before a reset never frees a claim made after it',
    () async {
      final channel = CloudflareQualityChannel(onRating: (_, _) {});
      final stale = channel.claim(ann, 'remote-1')!;
      await channel.reset();
      final fresh = channel.claim(ann, 'remote-1')!;

      channel.release(ann, stale);

      expect(channel.claim(ann, 'remote-1'), isNull);
      channel.release(ann, fresh);
      expect(channel.claim(ann, 'remote-1'), isNotNull);
    },
  );
}
