import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  Future<List<bool>> loginStatesAfter(List<LoginState> emitted) async {
    final client = buildTestClient()..accessToken = 'a0';
    final container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final seen = <bool>[];
    container.listen(isLoggedInProvider, (_, next) {
      final loggedIn = next.value;
      if (loggedIn != null) seen.add(loggedIn);
    }, fireImmediately: true);
    await container.read(isLoggedInProvider.future);
    await pumpEventQueue();

    for (final state in emitted) {
      client.onLoginStateChanged.add(state);
      await pumpEventQueue();
    }
    return seen;
  }

  test('a token refresh never reads as signed out', () async {
    final seen = await loginStatesAfter([
      LoginState.softLoggedOut,
      LoginState.loggedIn,
    ]);

    expect(seen, isNot(contains(false)));
  });

  test('a refresh that fails without a verdict stays signed in', () async {
    final seen = await loginStatesAfter([LoginState.softLoggedOut]);

    expect(seen.last, isTrue);
  });

  test('a cleared session signs out', () async {
    final seen = await loginStatesAfter([
      LoginState.softLoggedOut,
      LoginState.loggedOut,
    ]);

    expect(seen.last, isFalse);
  });
}
