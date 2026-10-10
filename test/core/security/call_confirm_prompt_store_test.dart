import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/security/call_confirm_prompt_store.dart';

void main() {
  late CallConfirmPromptStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = CallConfirmPromptStore(await SharedPreferences.getInstance());
  });

  test('declining is remembered for that person only', () async {
    await store.decline('@sam:example.org');

    expect(store.declined('@sam:example.org'), isTrue);
    expect(store.declined('@ann:example.org'), isFalse);
  });
}
