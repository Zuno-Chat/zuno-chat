import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/blurhash_image.dart';

import '../../helpers/fake_attachments.dart';
import '../../helpers/pump_until.dart';

void main() {
  late AttachmentServer server;

  setUp(() => server = installAttachmentServer());

  Event photo(Map<String, Object?> info) => server.attachment(info: info);

  test('reads the blurhash and size a photo carries', () {
    final event = photo(photoWithBlurhash);

    final image = BlurhashImage.of(event, thumbnail: false)!;

    expect((image.hash, image.width, image.height), (testBlurhash, 400, 300));
    expect(BlurhashImage.of(event, thumbnail: false), image);
  });

  test('a video thumbnail takes the size of the thumbnail', () {
    final event = server.attachment(
      msgtype: MessageTypes.Video,
      thumbnailId: 'clip-thumb',
      info: {
        'w': 1920,
        'h': 1080,
        'xyz.amorgan.blurhash': testBlurhash,
        'thumbnail_info': {'w': 320, 'h': 180},
      },
    );

    final thumbnail = BlurhashImage.of(event, thumbnail: true)!;
    final full = BlurhashImage.of(event, thumbnail: false)!;

    expect((thumbnail.width, thumbnail.height), (320, 180));
    expect((full.width, full.height), (1920, 1080));
  });

  test('a blurhash only in the thumbnail info still counts', () {
    final event = photo({
      'w': 400,
      'h': 300,
      'thumbnail_info': {'xyz.amorgan.blurhash': testBlurhash},
    });

    expect(BlurhashImage.of(event, thumbnail: true)?.hash, testBlurhash);
  });

  test('none without a blurhash, a readable one, or a size', () {
    expect(
      BlurhashImage.of(photo({'w': 400, 'h': 300}), thumbnail: true),
      null,
    );
    expect(
      BlurhashImage.of(
        photo({...photoWithBlurhash, 'xyz.amorgan.blurhash': 'not a blurhash'}),
        thumbnail: true,
      ),
      null,
    );
    expect(
      BlurhashImage.of(
        photo({'xyz.amorgan.blurhash': testBlurhash}),
        thumbnail: true,
      ),
      null,
    );
    expect(
      BlurhashImage.of(photo({...photoWithBlurhash, 'w': 0}), thumbnail: true),
      null,
    );
  });

  testWidgets('paints a few pixels that lay out at the photo\'s own size', (
    tester,
  ) async {
    final image = BlurhashImage.of(
      photo({...photoWithBlurhash, 'w': 1600, 'h': 1200}),
      thumbnail: false,
    )!;

    final info = await pumpUntilImageLoads(tester, image);

    expect((info.image.width, info.image.height), (32, 24));
    expect(info.image.width / info.scale, 1600);
    expect(info.image.height / info.scale, 1200);
  });
}
