import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/account/account_capabilities.dart';
import 'package:zuno/core/matrix/client/matrix_client_provider.dart';
import 'package:zuno/core/platform/app_settings_opener.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/matrix_experience.dart';
import 'package:zuno/features/settings/presentation/account_settings_page.dart';
import 'package:zuno/features/settings/presentation/change_password_dialog.dart';

import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_sign_in_browser.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

const _me = '@alice:example.org';

const _accountPage = 'https://account.example.org/account/';

CachedProfileInformation _profile({String? name, Uri? avatar}) =>
    CachedProfileInformation.fromProfile(
      ProfileInformation(displayname: name, avatarUrl: avatar),
      outdated: false,
      updated: clock.now(),
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

  Future<void> pumpPage(
    WidgetTester tester, {
    Future<bool> Function()? openSettings,
    Future<AccountCapabilities>? capabilities,
    bool matrixExperience = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          accountCapabilitiesProvider.overrideWith(
            (ref) => capabilities ?? Future.value(const AccountCapabilities()),
          ),
          if (openSettings != null)
            appSettingsOpenerProvider.overrideWithValue(openSettings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              MatrixExperience(on: matrixExperience, child: child!),
          home: const AccountSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String title) => find.widgetWithText(ListTile, title);

  String? subtitleOf(WidgetTester tester, String title) =>
      (tester.widget<ListTile>(row(title)).subtitle as Text?)?.data;

  group('the account capabilities', () {
    testWidgets('Change password is offered by default', (tester) async {
      await pumpPage(tester);

      expect(row('Change password'), findsOneWidget);
    });

    testWidgets('Change password never shows on an OAuth server while the '
        'answer loads', (tester) async {
      final answer = Completer<AccountCapabilities>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matrixClientProvider.overrideWithValue(client),
            accountCapabilitiesProvider.overrideWith((ref) => answer.future),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AccountSettingsPage(),
          ),
        ),
      );
      await tester.pump();

      expect(row('Change password'), findsNothing);
      expect(row('Manage account'), findsNothing);

      answer.complete(
        AccountCapabilities(
          canChangePassword: false,
          canMintSignInCodes: false,
          accountPage: AccountPage(Uri.parse(_accountPage), const {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(row('Change password'), findsNothing);
      expect(row('Manage account'), findsOneWidget);
    });

    testWidgets('an answer that failed offers Change password', (tester) async {
      await pumpPage(
        tester,
        capabilities: Future<AccountCapabilities>.error(
          StateError('unreadable'),
        )..ignore(),
      );

      expect(row('Change password'), findsOneWidget);
      expect(row('Manage account'), findsNothing);
    });

    testWidgets('Change password is hidden where the server disallows it', (
      tester,
    ) async {
      await pumpPage(
        tester,
        capabilities: Future.value(
          const AccountCapabilities(canChangePassword: false),
        ),
      );

      expect(row('Change password'), findsNothing);
      expect(row('Manage account'), findsNothing);
    });

    testWidgets('OAuth server shows Manage account, not Change password', (
      tester,
    ) async {
      final launched = mockSignInBrowser(tester);
      await pumpPage(
        tester,
        capabilities: Future.value(
          AccountCapabilities(
            canChangePassword: false,
            canMintSignInCodes: false,
            accountPage: AccountPage(Uri.parse(_accountPage), const {
              AccountManagementActionsSupported.orgMatrixProfile,
              AccountManagementActionsSupported.orgMatrixDevicesList,
            }),
          ),
        ),
      );

      expect(row('Change password'), findsNothing);
      await tester.tap(row('Manage account'));
      await tester.pumpAndSettle();

      expect(launched, ['$_accountPage?action=org.matrix.profile']);
    });

    testWidgets('a server that allows password change shows no Manage '
        'account', (tester) async {
      await pumpPage(tester);

      expect(row('Manage account'), findsNothing);
    });
  });

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
    final platform = recordChannel(SystemChannels.platform);
    await pumpPage(tester);

    await tester.tap(row('Username'));
    await tester.pumpAndSettle();

    expect(platform.valuesOf('Clipboard.setData', 'text'), ['@alice']);
    expect(find.text('Username copied'), findsOneWidget);
  });

  testWidgets('with the Matrix experience on, the username keeps its server '
      'and copies whole', (tester) async {
    final platform = recordChannel(SystemChannels.platform);
    await pumpPage(tester, matrixExperience: true);

    expect(subtitleOf(tester, 'Username'), _me);
    await tester.tap(row('Username'));
    await tester.pumpAndSettle();

    expect(platform.valuesOf('Clipboard.setData', 'text'), [_me]);
  });

  group('Change password', () {
    Future<void> fillIn(WidgetTester tester) async {
      Finder field(String label) =>
          find.ancestor(of: find.text(label), matching: find.byType(TextField));
      await tester.tap(row('Change password'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Current password'), 'old secret words');
      await tester.enterText(field('New password'), 'Correct horse battery 9');
      await tester.enterText(
        field('Confirm new password'),
        'Correct horse battery 9',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
    }

    testWidgets('changes it with the current one and says so', (tester) async {
      await pumpPage(tester);
      await fillIn(tester);

      expect(client.passwordChanges, [
        ('Correct horse battery 9', 'old secret words'),
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
      expect(find.text('Wrong password.'), findsOneWidget);
      expect(find.text('Password changed'), findsNothing);
    });

    testWidgets("the server's password policy refusal asks for a stronger "
        'password', (tester) async {
      client.passwordError = MatrixException.fromJson({
        'errcode': 'M_PASSWORD_TOO_SHORT',
        'error': 'Password too short',
      });
      await pumpPage(tester);
      await fillIn(tester);

      expect(find.byType(ChangePasswordDialog), findsOneWidget);
      expect(
        find.text('Your server needs a stronger password. Try a longer one.'),
        findsOneWidget,
      );
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

  group('the language', () {
    const channel = MethodChannel('zuno/locale');
    const shipped = [
      {'tag': 'en', 'locale': 'en'},
      {'tag': 'el', 'locale': 'el'},
    ];
    late List<MethodCall> localeCalls;
    late Map<String, Object?> localeReply;

    setUp(() {
      localeCalls = [];
      localeReply = {'supported': true, 'tag': null, 'options': shipped};
    });

    void mockLocaleChannel(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        localeCalls.add(call);
        if (call.method == 'set') {
          localeReply = {...localeReply, 'tag': (call.arguments as Map)['tag']};
        }
        return call.method == 'get' ? localeReply : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
    }

    Finder choices() => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(ListTile),
    );

    String? tickedChoice(WidgetTester tester) {
      final ticked = find.ancestor(
        of: find.byIcon(Icons.check_outlined),
        matching: find.byType(ListTile),
      );
      if (ticked.evaluate().isEmpty) return null;
      return (tester.widget<ListTile>(ticked).title as Text?)?.data;
    }

    testWidgets('on Android 13 and up the row reads Device language until '
        'one is chosen', (tester) async {
      ambientCapabilities = androidCapabilities;
      mockLocaleChannel(tester);
      await pumpPage(tester);

      expect(subtitleOf(tester, 'Language'), 'Device language');
    });

    testWidgets('the list offers Device language and every language by its '
        'own name', (tester) async {
      ambientCapabilities = androidCapabilities;
      mockLocaleChannel(tester);
      await pumpPage(tester);

      await tester.tap(row('Language'));
      await tester.pumpAndSettle();

      expect(choices(), findsNWidgets(3));
      expect(find.text('Device language'), findsWidgets);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Ελληνικά'), findsOneWidget);
    });

    testWidgets('choosing Ελληνικά sets the app language to el and shows '
        'it', (tester) async {
      ambientCapabilities = androidCapabilities;
      mockLocaleChannel(tester);
      await pumpPage(tester);

      await tester.tap(row('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ελληνικά'));
      await tester.pumpAndSettle();

      final set = localeCalls.singleWhere((c) => c.method == 'set');
      expect(set.arguments, {'tag': 'el'});
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets("the rows are the platform's list, and a choice sends its "
        'exact tag', (tester) async {
      ambientCapabilities = androidCapabilities;
      localeReply = {
        'supported': true,
        'tag': null,
        'options': [
          {'tag': 'en-US', 'locale': 'en'},
          {'tag': 'el', 'locale': 'el'},
        ],
      };
      mockLocaleChannel(tester);
      await pumpPage(tester);

      await tester.tap(row('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      final set = localeCalls.singleWhere((c) => c.method == 'set');
      expect(set.arguments, {'tag': 'en-US'});
    });

    testWidgets('the chosen row is the one with the exact tag', (tester) async {
      ambientCapabilities = androidCapabilities;
      localeReply = {'supported': true, 'tag': 'el', 'options': shipped};
      mockLocaleChannel(tester);
      await pumpPage(tester);

      await tester.tap(row('Language'));
      await tester.pumpAndSettle();

      expect(tickedChoice(tester), 'Ελληνικά');
    });

    testWidgets('a regional tag Android reports ticks the row of the '
        'language it resolves to', (tester) async {
      ambientCapabilities = androidCapabilities;
      localeReply = {
        'supported': true,
        'tag': 'el-GR',
        'locale': 'el',
        'options': shipped,
      };
      mockLocaleChannel(tester);
      await pumpPage(tester);

      expect(subtitleOf(tester, 'Language'), 'Ελληνικά');
      await tester.tap(row('Language'));
      await tester.pumpAndSettle();

      expect(tickedChoice(tester), 'Ελληνικά');
    });

    testWidgets('a tag that resolves to no row ticks nothing, not Device '
        'language', (tester) async {
      ambientCapabilities = androidCapabilities;
      localeReply = {'supported': true, 'tag': 'xx', 'options': shipped};
      mockLocaleChannel(tester);
      await pumpPage(tester);

      await tester.tap(row('Language'));
      await tester.pumpAndSettle();

      expect(tickedChoice(tester), isNull);
    });

    testWidgets('choosing Device language sends no tag', (tester) async {
      ambientCapabilities = androidCapabilities;
      localeReply = {'supported': true, 'tag': 'el', 'options': shipped};
      mockLocaleChannel(tester);
      await pumpPage(tester);

      await tester.tap(row('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Device language').last);
      await tester.pumpAndSettle();

      final set = localeCalls.singleWhere((c) => c.method == 'set');
      expect(set.arguments, {'tag': null});
    });

    testWidgets('a chosen language shows as the subtitle', (tester) async {
      ambientCapabilities = androidCapabilities;
      localeReply = {'supported': true, 'tag': 'el', 'options': shipped};
      mockLocaleChannel(tester);
      await pumpPage(tester);

      expect(find.text('Ελληνικά'), findsOneWidget);
    });

    testWidgets('below Android 13 there is no Language row', (tester) async {
      ambientCapabilities = androidCapabilities;
      localeReply = {'supported': false};
      mockLocaleChannel(tester);
      await pumpPage(tester);

      expect(row('Language'), findsNothing);
      expect(find.text('Language'), findsNothing);
    });

    group('on iOS', () {
      void setLocales(WidgetTester tester, List<Locale> locales) {
        tester.platformDispatcher.localesTestValue = locales;
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      }

      testWidgets('the row shows the current language and the open icon', (
        tester,
      ) async {
        ambientCapabilities = iosCapabilities;
        mockLocaleChannel(tester);
        await pumpPage(tester);

        expect(subtitleOf(tester, 'Language'), 'English');
        expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      });

      testWidgets('with several device languages the tap opens the app '
          'settings straight away', (tester) async {
        ambientCapabilities = iosCapabilities;
        setLocales(tester, const [Locale('en'), Locale('el')]);
        mockLocaleChannel(tester);
        var opened = 0;
        await pumpPage(
          tester,
          openSettings: () async {
            opened++;
            return true;
          },
        );

        await tester.tap(row('Language'));
        await tester.pumpAndSettle();

        expect(opened, 1);
        expect(find.text('Open Settings'), findsNothing);
        expect(localeCalls, isEmpty);
      });

      testWidgets('with one device language the tap explains the two steps '
          'first, and Open Settings opens the app settings', (tester) async {
        ambientCapabilities = iosCapabilities;
        setLocales(tester, const [Locale('en')]);
        mockLocaleChannel(tester);
        var opened = 0;
        await pumpPage(
          tester,
          openSettings: () async {
            opened++;
            return true;
          },
        );

        await tester.tap(row('Language'));
        await tester.pumpAndSettle();

        expect(opened, 0);
        expect(
          find.text(
            '1. Add the language in Settings → General → Language & '
            'Region.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('2. Choose it in Settings → Apps → Zuno → Language.'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Open Settings'));
        await tester.pumpAndSettle();

        expect(opened, 1);
        expect(find.text('Open Settings'), findsNothing);
        expect(localeCalls, isEmpty);
      });
    });
  });
}
