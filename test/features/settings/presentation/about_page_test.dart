import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/about_page.dart';

import '../../../helpers/card_layout.dart';

void main() {
  Finder switchTile(String title) =>
      find.widgetWithText(SwitchListTile, title, skipOffstage: false);

  Future<ProviderContainer> pumpAbout(
    WidgetTester tester, {
    AboutPage page = const AboutPage(),
    Map<String, Object> prefs = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(prefs);
    final sharedPrefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(sharedPrefs)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: page),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('every setting sits on a card', (tester) async {
    await pumpAbout(tester);

    expectEveryRowOnACard();
  });

  testWidgets('shows the amber brand mark, not the placeholder chat icon', (
    tester,
  ) async {
    await pumpAbout(tester);

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = picture.bytesLoader as SvgAssetLoader;
    expect(loader.assetName, 'assets/logo/zuno-mark-amber.svg');
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
  });

  testWidgets('still shows the version/SDK rows around the mark', (
    tester,
  ) async {
    await pumpAbout(tester);

    expect(find.text('App version'), findsOneWidget);
    expect(find.text('Chat library version'), findsOneWidget);
  });

  testWidgets('the library versions are the ones the app is built with', (
    tester,
  ) async {
    final lock = File('pubspec.lock').readAsLinesSync();
    String locked(String package) => lock
        .skip(lock.indexOf('  $package:'))
        .firstWhere((line) => line.startsWith('    version: '))
        .split('"')[1];

    await pumpAbout(tester);

    ListTile row(String title) =>
        tester.widget<ListTile>(find.widgetWithText(ListTile, title));
    expect(
      (row('Chat library version').subtitle! as Text).data,
      locked('matrix'),
    );
    expect(
      (row('Encryption library version').subtitle! as Text).data,
      locked('vodozemac'),
    );
  });

  testWidgets('shows the donation row as one static line', (tester) async {
    await pumpAbout(tester);

    expect(find.text('Donate'), findsOneWidget);
    expect(find.text('Donations help pay for running Zuno.'), findsOneWidget);
  });

  testWidgets('tapping Donate opens the donation section of the website', (
    tester,
  ) async {
    final opened = <Uri>[];
    await pumpAbout(
      tester,
      page: AboutPage(
        openUrl: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );

    await tester.tap(find.text('Donate'));
    await tester.pump();

    expect(opened, [Uri.parse('https://zuno.chat/#donate')]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('says what to do when no browser opens the link', (tester) async {
    await pumpAbout(tester, page: AboutPage(openUrl: (uri) async => false));

    await tester.tap(find.text('Donate'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Link not opened. Visit zuno.chat/#donate in a browser.'),
      findsOneWidget,
    );
  });

  testWidgets('says what to do when opening the link throws', (tester) async {
    await pumpAbout(
      tester,
      page: AboutPage(openUrl: (uri) async => throw Exception('no handler')),
    );

    await tester.tap(find.text('Donate'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Link not opened. Visit zuno.chat/#donate in a browser.'),
      findsOneWidget,
    );
  });

  testWidgets('Privacy policy and Terms open their pages on the website', (
    tester,
  ) async {
    final opened = <Uri>[];
    await pumpAbout(
      tester,
      page: AboutPage(
        openUrl: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );

    await tester.tap(find.text('Privacy policy'));
    await tester.pump();
    await tester.tap(find.text('Terms'));
    await tester.pump();

    expect(opened, [
      Uri.parse('https://zuno.chat/privacy'),
      Uri.parse('https://zuno.chat/terms'),
    ]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('names the privacy policy address when no browser opens it', (
    tester,
  ) async {
    await pumpAbout(tester, page: AboutPage(openUrl: (uri) async => false));

    await tester.tap(find.text('Privacy policy'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Link not opened. Visit zuno.chat/privacy in a browser.'),
      findsOneWidget,
    );
  });

  testWidgets('names the terms address when opening them throws', (
    tester,
  ) async {
    await pumpAbout(
      tester,
      page: AboutPage(openUrl: (uri) async => throw Exception('no handler')),
    );

    await tester.tap(find.text('Terms'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Link not opened. Visit zuno.chat/terms in a browser.'),
      findsOneWidget,
    );
  });

  testWidgets('Send crash reports is a real, enabled toggle — off by default', (
    tester,
  ) async {
    await pumpAbout(tester);

    final tile = tester.widget<SwitchListTile>(
      switchTile('Send crash reports'),
    );
    expect(tile.value, isFalse);
    expect(tile.onChanged, isNotNull);
  });

  testWidgets('the crash reporting switch promises only what it controls', (
    tester,
  ) async {
    await pumpAbout(tester);

    expect(
      find.textContaining('No crash report is sent while this is off'),
      findsOneWidget,
    );
    expect(find.textContaining('Nothing is sent'), findsNothing);
  });

  testWidgets('reads a previously-stored crash reporting opt-in', (
    tester,
  ) async {
    await pumpAbout(tester, prefs: {'settings.crash_reporting': true});

    final tile = tester.widget<SwitchListTile>(
      switchTile('Send crash reports'),
    );
    expect(tile.value, isTrue);
  });

  testWidgets('tapping the crash reporting toggle flips and persists it', (
    tester,
  ) async {
    final container = await pumpAbout(tester);

    await tester.tap(switchTile('Send crash reports'));
    await tester.pump();

    expect(container.read(crashReportingProvider), isTrue);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getBool('settings.crash_reporting'),
      isTrue,
    );
  });

  testWidgets('tapping the crash reporting toggle again turns it back off', (
    tester,
  ) async {
    final container = await pumpAbout(
      tester,
      prefs: {'settings.crash_reporting': true},
    );

    await tester.tap(switchTile('Send crash reports'));
    await tester.pump();

    expect(container.read(crashReportingProvider), isFalse);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getBool('settings.crash_reporting'),
      isFalse,
    );
  });

  testWidgets('Show hidden messages is off by default and flips', (
    tester,
  ) async {
    final container = await pumpAbout(tester);

    expect(
      tester.widget<SwitchListTile>(switchTile('Show hidden messages')).value,
      isFalse,
    );
    await tester.tap(switchTile('Show hidden messages'));
    await tester.pump();

    expect(container.read(showHiddenMessagesProvider), isTrue);
  });

  testWidgets('tapping Source code opens the repository', (tester) async {
    final opened = <Uri>[];
    await pumpAbout(
      tester,
      page: AboutPage(
        openUrl: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );

    await tester.tap(find.text('Source code'));
    await tester.pump();

    expect(opened, [Uri.parse('https://github.com/Zuno-Chat/zuno-chat')]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('names the repository address when no browser opens it', (
    tester,
  ) async {
    await pumpAbout(tester, page: AboutPage(openUrl: (uri) async => false));

    await tester.tap(find.text('Source code'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'Link not opened. Visit github.com/Zuno-Chat/zuno-chat in a browser.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Open source licenses shows the license page with the notice', (
    tester,
  ) async {
    await pumpAbout(tester);

    await tester.tap(find.text('Open source licenses'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(LicensePage), findsOneWidget);
    expect(
      find.textContaining('GNU Affero General Public License'),
      findsOneWidget,
    );
    expect(find.textContaining('Zuno Chat Authors'), findsOneWidget);
  });
}
