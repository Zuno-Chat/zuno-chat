import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/force_sync.dart';

import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  _RecordingClient() : super('test', database: FakeDatabaseApi());

  final steps = <String>[];
  Object? oneShotError;

  @override
  Future<void> abortSync() async => steps.add('abort');

  @override
  Future<void> oneShotSync({Duration? timeout}) async {
    steps.add('sync(${timeout?.inMilliseconds})');
    final error = oneShotError;
    if (error != null) throw error;
  }

  @override
  set backgroundSync(bool enabled) => steps.add('backgroundSync=$enabled');
}

void main() {
  test('aborts the in-flight long-poll, syncs immediately, then restores '
      'the loop', () async {
    final client = _RecordingClient();

    await forceSyncNow(client);

    expect(client.steps, ['abort', 'sync(0)', 'backgroundSync=true']);
  });

  test('restores the sync loop even when the sync itself fails', () async {
    final client = _RecordingClient()..oneShotError = Exception('offline');

    await expectLater(forceSyncNow(client), throwsException);

    expect(client.steps.last, 'backgroundSync=true');
  });

  test('a client that cannot sync is left with its loop running', () async {
    final client = buildTestClient();

    await expectLater(forceSyncNow(client), completes);
  });
}
