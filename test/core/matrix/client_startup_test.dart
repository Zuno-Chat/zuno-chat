import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/client_startup.dart';

void main() {
  group('startWithRetries', () {
    late List<Duration> pauses;
    late int attempts;

    setUp(() {
      pauses = [];
      attempts = 0;
    });

    Future<String> start(String Function(int attempt) attempt) =>
        startWithRetries(
          attempt: () async => attempt(++attempts),
          pause: (delay) async => pauses.add(delay),
        );

    test('a start that works is used at once', () async {
      expect(await start((_) => 'client'), 'client');

      expect(attempts, 1);
      expect(pauses, isEmpty);
    });

    test('a failed start is tried again after a short pause, then a longer '
        'one', () async {
      expect(
        await start(
          (attempt) =>
              attempt < 3 ? throw StateError('busy') : 'client $attempt',
        ),
        'client 3',
      );

      expect(pauses, appStartRetryDelays);
    });

    test('gives up after the last try with that try\'s error', () async {
      await expectLater(
        start((attempt) => throw StateError('broken $attempt')),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'broken 3'),
        ),
      );

      expect(attempts, appStartRetryDelays.length + 1);
    });
  });

  group('startClientOrAsk', () {
    late List<StartupChoice> answers;
    late List<Object> asked;
    late List<Object> reported;
    late List<String> calls;

    setUp(() {
      answers = [];
      asked = [];
      reported = [];
      calls = [];
    });

    Future<String> run(
      Future<String> first, {
      Future<String> Function()? retry,
      Future<String> Function()? startOver,
    }) => startClientOrAsk(
      first: first,
      askUser: (error) async {
        asked.add(error);
        return answers.removeAt(0);
      },
      retry:
          retry ??
          () async {
            calls.add('retry');
            return 'retried';
          },
      startOver:
          startOver ??
          () async {
            calls.add('start over');
            return 'fresh';
          },
      report: (error, _) => reported.add(error),
    );

    test('a start that works never asks anything', () async {
      expect(await run(Future.value('client')), 'client');

      expect(asked, isEmpty);
      expect(calls, isEmpty);
      expect(reported, isEmpty);
    });

    test('after a failed start, the user can try again', () async {
      answers = [StartupChoice.tryAgain];
      final failure = StateError('broken');

      expect(await run(Future.error(failure)), 'retried');

      expect(asked, [failure]);
      expect(reported, [failure]);
      expect(calls, ['retry']);
    });

    test('after a failed start, the user can start over', () async {
      answers = [StartupChoice.startOver];

      expect(await run(Future.error(StateError('broken'))), 'fresh');

      expect(calls, ['start over']);
    });

    test('nothing is started over unless the user asks for it, however often '
        'starting fails', () async {
      answers = [
        StartupChoice.tryAgain,
        StartupChoice.tryAgain,
        StartupChoice.tryAgain,
      ];
      var retries = 0;

      expect(
        await run(
          Future.error(StateError('broken')),
          retry: () async {
            retries++;
            calls.add('retry');
            if (retries < 3) throw StateError('still broken');
            return 'retried';
          },
        ),
        'retried',
      );

      expect(asked, hasLength(3));
      expect(reported, hasLength(3));
      expect(calls, ['retry', 'retry', 'retry']);
    });

    test('a start over that fails asks again', () async {
      answers = [StartupChoice.startOver, StartupChoice.tryAgain];

      expect(
        await run(
          Future.error(StateError('broken')),
          startOver: () async {
            calls.add('start over');
            throw StateError('key store unusable');
          },
        ),
        'retried',
      );

      expect(calls, ['start over', 'retry']);
      expect(asked, hasLength(2));
    });
  });
}
