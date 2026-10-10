import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/settings/library_versions.dart';
import 'package:zuno/features/settings/presentation/about_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/preferences_container.dart';

void main() {
  Finder switchTile(String title) =>
      find.widgetWithText(SwitchListTile, title, skipOffstage: false);

  String? subtitleOf(WidgetTester tester, String title) =>
      (tester.widget<ListTile>(find.widgetWithText(ListTile, title)).subtitle!
              as Text)
          .data;

  Future<ProviderContainer> pumpAbout(
    WidgetTester tester, {
    AboutPage page = const AboutPage(),
    Map<String, Object> prefs = const {},
    PlatformCapabilities? capabilities,
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await containerWithPreferences(
      prefs,
      overrides: [
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        ...overrides,
      ],
    );
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

  testWidgets('the library versions are the ones the app is built with', (
    tester,
  ) async {
    final lock = File('pubspec.lock').readAsLinesSync();
    String locked(String package) => lock
        .skip(lock.indexOf('  $package:'))
        .firstWhere((line) => line.startsWith('    version: '))
        .split('"')[1];

    await pumpAbout(tester);
    await tester.pump();

    expect(subtitleOf(tester, 'Chat library version'), locked('matrix'));
    expect(
      subtitleOf(tester, 'Encryption library version'),
      locked('vodozemac'),
    );
  });

  testWidgets('library versions that cannot be read say Unknown', (
    tester,
  ) async {
    await pumpAbout(
      tester,
      overrides: [
        libraryVersionsProvider.overrideWith(
          (ref) => Future.error(const FormatException('unreadable')),
        ),
      ],
    );
    await tester.pump();

    expect(subtitleOf(tester, 'Chat library version'), 'Unknown');
    expect(subtitleOf(tester, 'Encryption library version'), 'Unknown');
  });

  testWidgets('shows the donation row as one static line', (tester) async {
    await pumpAbout(tester);

    expect(find.text('Donate'), findsOneWidget);
    expect(find.text('Donations help pay for running Zuno.'), findsOneWidget);
  });

  testWidgets('hides Donate where the store forbids payment links', (
    tester,
  ) async {
    await pumpAbout(tester, capabilities: iosCapabilities);

    expect(find.text('Donate'), findsNothing);
    expect(find.text('Donations help pay for running Zuno.'), findsNothing);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expectEveryRowOnACard();
  });

  testWidgets('each link row opens its page, with no warning', (tester) async {
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

    for (final row in ['Donate', 'Privacy policy', 'Terms', 'Source code']) {
      await tester.tap(find.text(row));
      await tester.pump();
    }

    expect(opened, [
      Uri.parse('https://zuno.chat/#donate'),
      Uri.parse('https://zuno.chat/privacy'),
      Uri.parse('https://zuno.chat/terms'),
      Uri.parse('https://github.com/Zuno-Chat/zuno-chat'),
    ]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('says what to do when no browser opens the link', (tester) async {
    await pumpAbout(tester, page: AboutPage(openUrl: (_) async => false));

    await tester.tap(find.text('Donate'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Link not opened. Visit zuno.chat/#donate in a browser.'),
      findsOneWidget,
    );
  });

  testWidgets('the crash reporting toggle starts off and flips both ways', (
    tester,
  ) async {
    final container = await pumpAbout(tester);
    bool shown() => tester
        .widget<SwitchListTile>(switchTile('Send crash and error reports'))
        .value;
    expect(shown(), isFalse);

    await tester.tap(switchTile('Send crash and error reports'));
    await tester.pump();

    expect(container.read(crashReportingProvider), isTrue);
    expect(shown(), isTrue);

    await tester.tap(switchTile('Send crash and error reports'));
    await tester.pump();

    expect(container.read(crashReportingProvider), isFalse);
    expect(shown(), isFalse);
  });

  testWidgets('the crash reporting switch promises only what it controls', (
    tester,
  ) async {
    await pumpAbout(tester);

    expect(
      find.textContaining('No report is sent while this is off'),
      findsOneWidget,
    );
    expect(find.textContaining('Nothing is sent'), findsNothing);
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
