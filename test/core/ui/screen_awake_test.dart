import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/ui/screen_awake.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/fake_screen_awake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeScreenAwake phone;
  final screen = ScreenAwake.instance;

  setUp(() => phone = installFakeScreenAwake());

  test('keeps the screen on while claimed and lets it sleep after', () async {
    final owner = Object();

    screen.claim(owner);
    await pumpEventQueue();
    expect(phone.toggles, [true]);

    screen.release(owner);
    await pumpEventQueue();
    expect(phone.toggles, [true, false]);
  });

  test('a phone that refuses is reported, not thrown', () async {
    phone.refuses = true;

    final reports = await reportsDuring(() async {
      screen.claim(Object());
      await pumpEventQueue();
    });

    expect(reports, ['keep the screen on']);
  });
}
