import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/errors/global_error_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMessengerApp(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      scaffoldMessengerKey: globalScaffoldMessengerKey,
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );

  group('formatErrorMessage', () {
    test('with no stack trace, is just the error\'s own toString()', () {
      expect(formatErrorMessage('boom', null), 'boom');
    });

    test('with a stack trace, includes both', () {
      final stack = StackTrace.fromString('#0 someFunction');
      expect(formatErrorMessage('boom', stack), 'boom\n\n#0 someFunction');
    });
  });

  group('firstLineOf', () {
    test('single-line message is returned unchanged', () {
      expect(firstLineOf('boom'), 'boom');
    });

    test('multi-line message (error + stack) keeps only the first line', () {
      expect(firstLineOf('boom\n\n#0 someFunction\n#1 other'), 'boom');
    });
  });

  group('buildErrorSnackBar', () {
    test(
      'persist is false, so the Copy action doesn\'t stop it auto-dismissing',
      () {
        expect(buildErrorSnackBar('boom').persist, isFalse);
      },
    );

    testWidgets(
      'auto-dismisses on its own after the duration, with no tap at all',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      ScaffoldMessenger.of(context)
                          .showSnackBar(buildErrorSnackBar('boom')),
                  child: const Text('trigger'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        expect(find.text('boom'), findsOneWidget);

        await tester.pump(const Duration(seconds: 9));
        await tester.pumpAndSettle();
        expect(find.text('boom'), findsNothing);
      },
    );

    testWidgets('shows only the first line, and Copy copies the full text', (
      tester,
    ) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      const fullMessage = 'boom\n\n#0 someFunction';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(buildErrorSnackBar(fullMessage));
                },
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text('boom'), findsOneWidget);
      expect(find.text(fullMessage), findsNothing);

      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, fullMessage);
    });
  });

  group('installGlobalErrorHandlers', () {
    setUp(() {
      final previousFlutterOnError = FlutterError.onError;
      final previousPlatformOnError = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = previousFlutterOnError;
        PlatformDispatcher.instance.onError = previousPlatformOnError;
      });
    });

    test('chains the handlers it replaces instead of dropping them', () {
      var flutterChained = 0;
      var platformChained = 0;
      FlutterError.onError = (_) => flutterChained++;
      PlatformDispatcher.instance.onError = (_, _) {
        platformChained++;
        return true;
      };

      installGlobalErrorHandlers();
      FlutterError.onError!(FlutterErrorDetails(exception: 'boom'));
      PlatformDispatcher.instance.onError!('boom', StackTrace.empty);

      expect(flutterChained, 1);
      expect(platformChained, 1);
    });

    test('installs over an empty slot without complaining', () {
      FlutterError.onError = null;
      PlatformDispatcher.instance.onError = null;

      installGlobalErrorHandlers();

      expect(
        () => FlutterError.onError!(FlutterErrorDetails(exception: 'boom')),
        returnsNormally,
      );
      expect(
        () => PlatformDispatcher.instance.onError!('boom', StackTrace.empty),
        returnsNormally,
      );
    });

    testWidgets('a silent FlutterError does not raise the SnackBar', (
      tester,
    ) async {
      FlutterError.onError = (_) {};
      await pumpMessengerApp(tester);
      installGlobalErrorHandlers();

      FlutterError.onError!(
        FlutterErrorDetails(exception: 'silent boom', silent: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('silent boom'), findsNothing);
    });

    testWidgets('a non-silent FlutterError still raises the SnackBar', (
      tester,
    ) async {
      FlutterError.onError = (_) {};
      await pumpMessengerApp(tester);
      installGlobalErrorHandlers();

      FlutterError.onError!(
        FlutterErrorDetails(exception: 'loud boom', silent: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('loud boom'), findsOneWidget);
    });
  });

  group('reportZoneError', () {
    test('is a no-op for crash reporting while Sentry is disabled', () {
      expect(() => reportZoneError('boom', StackTrace.empty), returnsNormally);
    });
  });

  group('reportUnhandledError', () {
    tearDown(() => showUnhandledErrorSnackBars = kDebugMode);

    testWidgets('shows the snackbar in a debug build', (tester) async {
      expect(showUnhandledErrorSnackBars, isTrue);

      await pumpMessengerApp(tester);

      reportUnhandledError('boom', null);
      await tester.pumpAndSettle();

      expect(find.text('boom'), findsOneWidget);
    });

    testWidgets('shows nothing in a release build', (tester) async {
      showUnhandledErrorSnackBars = false;

      await pumpMessengerApp(tester);

      reportUnhandledError('boom', null);
      await tester.pumpAndSettle();

      expect(find.text('boom'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('showErrorSnackBar', () {
    testWidgets('shows the error on the attached ScaffoldMessenger', (
      tester,
    ) async {
      await pumpMessengerApp(tester);

      showErrorSnackBar('something went wrong');
      await tester.pumpAndSettle();

      expect(find.text('something went wrong'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('is a no-op when no widget tree is attached to the key', (
      tester,
    ) async {
      showErrorSnackBar('too early');
      await tester.pump();
    });

    testWidgets('does not trip "Build scheduled during frame" when called from '
        'inside a widget build', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          home: Builder(
            builder: (context) {
              showErrorSnackBar('called mid-build');
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('called mid-build'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
