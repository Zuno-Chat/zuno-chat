import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/third_party_keyboards.dart';

import '../../helpers/fake_privacy_channel.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordedMethodCalls native;

  setUp(() => native = installFakePrivacyChannel());

  test('Incognito keyboard blocks other keyboards, and turning it off '
      'allows them again', () async {
    final keyboards = ThirdPartyKeyboards(capabilities: iosCapabilities);

    await keyboards.followIncognito(true);
    await keyboards.followIncognito(false);

    expect(native.thirdPartyKeyboards, [false, true]);
  });

  test(
    'a platform that cannot block other keyboards never calls native',
    () async {
      final keyboards = ThirdPartyKeyboards(capabilities: androidCapabilities);

      await keyboards.followIncognito(true);

      expect(native.calls, isEmpty);
    },
  );

  test('no native side at all is not an error', () async {
    removePrivacyChannel();
    final keyboards = ThirdPartyKeyboards(capabilities: iosCapabilities);

    await expectLater(keyboards.followIncognito(true), completes);
  });
}
