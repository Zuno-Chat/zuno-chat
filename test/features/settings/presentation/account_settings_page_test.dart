import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/features/settings/presentation/account_settings_page.dart';
import 'package:zuno/features/settings/presentation/change_password_dialog.dart';

import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_matrix.dart';

const _me = '@alice:example.org';

CachedProfileInformation _profile({String? name, Uri? avatar}) =>
    CachedProfileInformation.fromProfile(
      ProfileInformation(displayname: name, avatarUrl: avatar),
      outdated: false,
      updated: DateTime.now(),
    );

class _ProfileClient extends Client {
  _ProfileClient() : super('test', database: FakeDatabaseApi()) {
    setUserId(_me);
  }

  CachedProfileInformation cached = _profile(name: 'Alice');
  CachedProfileInformation? server;
  Object? readError;
  final maxCacheAges = <Duration>[];
  final fields = <Map<String, Object?>>[];
  Object? saveError;
  Completer<void>? saveGate;
  final avatars = <MatrixFile?>[];
  final passwordChanges = <(String, String?)>[];
  Object? passwordError;

  @override
  Future<CachedProfileInformation> getUserProfile(
    String userId, {
    Duration timeout = const Duration(seconds: 30),
    Duration maxCacheAge = const Duration(days: 1),
  }) async {
    maxCacheAges.add(maxCacheAge);
    final error = readError;
    if (error != null) throw error;
    return maxCacheAge == Duration.zero ? server ?? cached : cached;
  }

  @override
  Future<Map<String, Object?>> setProfileField(
    String userId,
    String keyName,
    Map<String, Object?> body,
  ) async {
    await saveGate?.future;
    final error = saveError;
    if (error != null) throw error;
    fields.add(body);
    server = _profile(
      name: body['displayname'] as String? ?? server?.displayname,
      avatar: server?.avatarUrl,
    );
    return {};
  }

  @override
  Future<void> setAvatar(MatrixFile? file) async {
    final error = saveError;
    if (error != null) throw error;
    avatars.add(file);
  }

  @override
  Future<void> changePassword(
    String newPassword, {
    String? oldPassword,
    AuthenticationData? auth,
    bool? logoutDevices,
  }) async {
    final error = passwordError;
    if (error != null) throw error;
    passwordChanges.add((newPassword, oldPassword));
  }
}

void main() {
  late _ProfileClient client;
  late FakeImagePicker picker;

  setUp(() {
    client = _ProfileClient();
    picker = installFakeImagePicker();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [matrixClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: AccountSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String title) => find.widgetWithText(ListTile, title);

  String? subtitleOf(WidgetTester tester, String title) =>
      (tester.widget<ListTile>(row(title)).subtitle as Text?)?.data;

  group('the profile', () {
    testWidgets('shows the display name and the username without the '
        'server', (tester) async {
      await pumpPage(tester);

      expect(subtitleOf(tester, 'Display name'), 'Alice');
      expect(subtitleOf(tester, 'Username'), '@alice');
      expect(find.textContaining('example.org'), findsNothing);
    });

    testWidgets('an empty display name reads Not set', (tester) async {
      client.cached = _profile(name: '');
      await pumpPage(tester);

      expect(subtitleOf(tester, 'Display name'), 'Not set');
    });

    testWidgets('a failed load says so plainly, without the raw error', (
      tester,
    ) async {
      client.readError = Exception('SocketException: Connection refused');
      await pumpPage(tester);

      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.text('Could not load your profile.'), findsOneWidget);
      expect(subtitleOf(tester, 'Display name'), 'Not set');
    });
  });

  group('the display name', () {
    Future<void> openEditor(WidgetTester tester) async {
      await tester.tap(row('Display name'));
      await tester.pumpAndSettle();
    }

    Finder field() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

    testWidgets('opens prefilled with the current name', (tester) async {
      await pumpPage(tester);
      await openEditor(tester);

      expect(tester.widget<TextField>(field()).controller!.text, 'Alice');
    });

    testWidgets('saving sends the trimmed name and shows it right away, not '
        'the cached old one', (tester) async {
      await pumpPage(tester);
      await openEditor(tester);

      await tester.enterText(field(), '  Alice Liddell ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(client.fields, [
        {'displayname': 'Alice Liddell'},
      ]);
      expect(client.maxCacheAges.last, Duration.zero);
      expect(subtitleOf(tester, 'Display name'), 'Alice Liddell');
      expect(find.text('Display name updated'), findsOneWidget);
    });

    testWidgets('the keyboard action saves too', (tester) async {
      await pumpPage(tester);
      await openEditor(tester);

      await tester.enterText(field(), 'Al');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(client.fields.single['displayname'], 'Al');
    });

    testWidgets('shows a spinner while saving and takes no second tap', (
      tester,
    ) async {
      client.saveGate = Completer();
      await pumpPage(tester);
      await openEditor(tester);

      await tester.enterText(field(), 'Al');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.descendant(
          of: row('Display name'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(row('Display name')).onTap, isNull);

      client.saveGate!.complete();
      await tester.pumpAndSettle();

      expect(tester.widget<ListTile>(row('Display name')).onTap, isNotNull);
    });

    testWidgets('a blank name is not saved', (tester) async {
      await pumpPage(tester);
      await openEditor(tester);

      await tester.enterText(field(), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(client.fields, isEmpty);
    });

    testWidgets('the same name is not sent again', (tester) async {
      await pumpPage(tester);
      await openEditor(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(client.fields, isEmpty);
      expect(find.text('Display name updated'), findsNothing);
    });

    testWidgets('Cancel saves nothing', (tester) async {
      await pumpPage(tester);
      await openEditor(tester);

      await tester.enterText(field(), 'Somebody else');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(client.fields, isEmpty);
      expect(subtitleOf(tester, 'Display name'), 'Alice');
    });

    testWidgets('a failed save says so and keeps the old name', (tester) async {
      client.saveError = Exception('offline');
      await pumpPage(tester);
      await openEditor(tester);

      await tester.enterText(field(), 'Al');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Display name not saved. Try again.'), findsOneWidget);
      expect(subtitleOf(tester, 'Display name'), 'Alice');
      expect(tester.widget<ListTile>(row('Display name')).onTap, isNotNull);
    });
  });

  group('the profile picture', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(row('Profile picture'));
      await tester.pumpAndSettle();
    }

    XFile photo() => XFile.fromData(
      img.encodeJpg(img.Image(width: 800, height: 400)),
      path: 'IMG_0001.jpg',
      mimeType: 'image/jpeg',
    );

    testWidgets('without a photo there is nothing to remove', (tester) async {
      await pumpPage(tester);
      await openSheet(tester);

      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.text('Remove photo'), findsNothing);
    });

    testWidgets('a photo can be removed', (tester) async {
      client.cached = _profile(
        name: 'Alice',
        avatar: Uri.parse('mxc://example.org/abc'),
      );
      await pumpPage(tester);
      await openSheet(tester);

      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();

      expect(client.avatars, [null]);
      expect(find.text('Photo updated'), findsOneWidget);
    });

    testWidgets('a gallery photo is shrunk before it is sent', (tester) async {
      picker.answer = [photo()];
      await pumpPage(tester);
      await openSheet(tester);

      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(picker.calls, ['image:gallery']);
      final sent = client.avatars.single! as MatrixImageFile;
      expect((sent.width, sent.height), (512, 256));
      expect(find.text('Photo updated'), findsOneWidget);
    });

    testWidgets('a camera shot that is abandoned sends nothing', (
      tester,
    ) async {
      await pumpPage(tester);
      await openSheet(tester);

      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();

      expect(picker.calls, ['image:camera']);
      expect(client.avatars, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.widget<ListTile>(row('Profile picture')).onTap, isNotNull);
    });

    testWidgets('a failed upload says so', (tester) async {
      picker.answer = [photo()];
      client.saveError = Exception('offline');
      await pumpPage(tester);
      await openSheet(tester);

      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(find.text('Photo not saved. Try again.'), findsOneWidget);
    });
  });

  testWidgets('tapping the username copies it without the server', (
    tester,
  ) async {
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpPage(tester);

    await tester.tap(row('Username'));
    await tester.pumpAndSettle();

    expect(copied, ['@alice']);
    expect(find.text('Username copied'), findsOneWidget);
  });

  group('Change password', () {
    Future<void> fillIn(WidgetTester tester) async {
      Finder field(String label) =>
          find.ancestor(of: find.text(label), matching: find.byType(TextField));
      await tester.tap(row('Change password'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Current password'), 'old secret words');
      await tester.enterText(field('New password'), 'correct horse battery 9');
      await tester.enterText(
        field('Confirm new password'),
        'correct horse battery 9',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
    }

    testWidgets('changes it with the current one and says so', (tester) async {
      await pumpPage(tester);
      await fillIn(tester);

      expect(client.passwordChanges, [
        ('correct horse battery 9', 'old secret words'),
      ]);
      expect(find.byType(ChangePasswordDialog), findsNothing);
      expect(find.text('Password changed'), findsOneWidget);
    });

    testWidgets('a refusal keeps the dialog open with the reason', (
      tester,
    ) async {
      client.passwordError = MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Invalid password',
      });
      await pumpPage(tester);
      await fillIn(tester);

      expect(find.byType(ChangePasswordDialog), findsOneWidget);
      expect(find.text('Password not changed. Try again.'), findsOneWidget);
      expect(find.text('Password changed'), findsNothing);
    });

    testWidgets('Cancel says nothing', (tester) async {
      await pumpPage(tester);

      await tester.tap(row('Change password'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(client.passwordChanges, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
