import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/data_storage_settings_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/preferences_container.dart';

class _CacheClient extends Client {
  _CacheClient() : super('test', database: FakeDatabaseApi()) {
    setUserId('@me:example.org');
  }

  int clears = 0;
  Object? error;
  Completer<void>? finishing;

  @override
  Future<void> clearCache() async {
    final error = this.error;
    if (error != null) throw error;
    clears++;
    await finishing?.future;
  }
}

void main() {
  late _CacheClient client;

  setUp(() => client = _CacheClient());

  Finder switchTile(String title) =>
      find.widgetWithText(SwitchListTile, title, skipOffstage: false);

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await containerWithPreferences(
      prefs,
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DataStorageSettingsPage()),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('every setting sits on a card', (tester) async {
    await pumpPage(tester);

    expectEveryRowOnACard();
  });

  testWidgets('each data toggle says what it does in plain words, whether '
      'on or off', (tester) async {
    const media =
        'Photos and videos send faster and use less data, but look less '
        'sharp.';
    const calls = 'Video calls use less data, but the picture is less sharp.';
    await pumpPage(tester);

    expect(find.text(media), findsOneWidget);
    expect(find.text(calls), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d+p|fps|[Cc]ompress')), findsNothing);

    await tester.tap(switchTile('Reduce media size'));
    await tester.tap(switchTile('Use less data for calls'));
    await tester.pump();

    expect(find.text(media), findsOneWidget);
    expect(find.text(calls), findsOneWidget);
  });

  for (final (title, provider, key) in [
    (
      'Reduce media size',
      reduceMediaSizeProvider,
      'settings.reduce_media_size',
    ),
    (
      'Use less data for calls',
      lowDataCallsProvider,
      'settings.low_data_calls',
    ),
  ]) {
    testWidgets('$title turns off and persists', (tester) async {
      final container = await pumpPage(tester);

      await tester.tap(switchTile(title));
      await tester.pump();

      expect(container.read(provider), isFalse);
      expect(tester.widget<SwitchListTile>(switchTile(title)).value, isFalse);
      expect(container.read(sharedPreferencesProvider).getBool(key), isFalse);
    });
  }

  testWidgets('Clear cache asks first, and Cancel clears nothing', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();
    expect(find.text('Clear cache?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Clear cache?'), findsNothing);
    expect(find.text('Cache cleared'), findsNothing);
    expect(client.clears, 0);
  });

  testWidgets('Clear cache says it is done only once the clear, space given '
      'back included, has finished', (tester) async {
    final finishing = client.finishing = Completer();
    await pumpPage(tester);

    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear cache'));
    await tester.pumpAndSettle();

    expect(client.clears, 1);
    expect(find.text('Cache cleared'), findsNothing);

    finishing.complete();
    await tester.pumpAndSettle();

    expect(find.text('Cache cleared'), findsOneWidget);
  });

  testWidgets('a failed Clear cache says so', (tester) async {
    client.error = StateError('database locked');
    await pumpPage(tester);

    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear cache'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Cache cleared'), findsNothing);
    expect(find.text('Cache not cleared. Try again.'), findsOneWidget);
  });

  testWidgets('Clear media cache empties memory and disk without asking', (
    tester,
  ) async {
    final cacheRoot = Directory.systemTemp.createTempSync('zuno_media_');
    addTearDown(() => cacheRoot.deleteSync(recursive: true));
    final saved = File('${cacheRoot.path}/attachment_cache/photo')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => cacheRoot.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProvider,
        null,
      ),
    );
    AttachmentCache.instance.put('mxc://x/y', Uint8List.fromList([1]));
    await pumpPage(tester);

    await tester.tap(find.text('Clear media cache'));
    await pumpWhileFetching(
      tester,
      rounds: 200,
      until: () => find.text('Media cache cleared').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(AttachmentCache.instance.get('mxc://x/y'), isNull);
    expect(saved.existsSync(), isFalse);
    expect(find.text('Media cache cleared'), findsOneWidget);
  });
}
