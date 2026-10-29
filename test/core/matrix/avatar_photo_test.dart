import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/avatar_photo.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/fake_attachments.dart';

void main() {
  test('an avatar loses the GPS location of the photo it came from and stays '
      'upright', () async {
    final photo = img.Image(width: 800, height: 400)
      ..exif.imageIfd.orientation = 6;
    photo.exif.gpsIfd[0x0001] = img.IfdValueAscii('N');
    photo.exif.gpsIfd[0x0002] = img.IfdValueRational(52, 1);

    final avatar = await prepareAvatarPhoto(
      img.encodeJpg(photo),
      name: 'IMG_0001.jpg',
      nativeImplementations: NativeImplementations.dummy,
    );

    final exif = img.decodeJpgExif(avatar.bytes);
    expect(exif?.imageIfd.sub.containsKey('gps') ?? false, isFalse);
    expect((avatar.width, avatar.height), (256, 512));
  });

  test('an avatar without a location is only shrunk', () async {
    final avatar = await prepareAvatarPhoto(
      img.encodeJpg(img.Image(width: 1024, height: 256)),
      name: 'IMG_0002.jpg',
      nativeImplementations: NativeImplementations.dummy,
    );

    expect((avatar.width, avatar.height), (512, 128));
  });

  group('applyAvatarAction', () {
    Future<BuildContext> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('Profile')),
        ),
      );
      return tester.element(find.text('Profile'));
    }

    Future<List<MatrixImageFile?>> run(
      WidgetTester tester,
      AvatarAction action, {
      Object? applyError,
    }) async {
      final context = await pumpHost(tester);
      final applied = <MatrixImageFile?>[];
      await reportsDuring(
        () => applyAvatarAction(
          context,
          action,
          nativeImplementations: NativeImplementations.dummy,
          label: 'update profile photo',
          apply: (photo) async {
            if (applyError != null) throw applyError;
            applied.add(photo);
          },
        ),
      );
      await tester.pump();
      return applied;
    }

    testWidgets('removing applies no photo and says it is updated', (
      tester,
    ) async {
      expect(await run(tester, AvatarAction.remove), [null]);
      expect(find.text('Photo updated'), findsOneWidget);
    });

    testWidgets('a cancelled pick changes nothing and says nothing', (
      tester,
    ) async {
      final picker = installFakeImagePicker();

      expect(await run(tester, AvatarAction.gallery), isEmpty);
      expect(picker.calls, ['image:gallery']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed save while offline asks to check the connection', (
      tester,
    ) async {
      await run(
        tester,
        AvatarAction.remove,
        applyError: const SocketException('offline'),
      );
      expect(
        find.text(
          lookupAppLocalizations(const Locale('en'))
              .errorsFailedCheckConnection('Photo not saved.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('denied photo access is not reported as a crash', (
      tester,
    ) async {
      final picker = installFakeImagePicker()
        ..error = PlatformException(code: 'photo_access_denied');
      final context = await pumpHost(tester);

      final reports = await reportsDuring(
        () => applyAvatarAction(
          context,
          AvatarAction.gallery,
          nativeImplementations: NativeImplementations.dummy,
          label: 'update profile photo',
          apply: (_) async {},
        ),
      );
      await tester.pump();

      expect(picker.calls, ['image:gallery']);
      expect(reports, isEmpty);
      expect(find.text('Photo not saved.'), findsOneWidget);
    });
  });
}
