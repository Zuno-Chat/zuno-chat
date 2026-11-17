import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/updates/update_source.dart';

void main() {
  const android = {UpdateSource.play, UpdateSource.website};
  const ios = {UpdateSource.appStore};

  for (final (installer, offered, expected) in [
    ('com.android.vending', android, UpdateSource.play),
    ('com.google.android.packageinstaller', android, UpdateSource.website),
    ('com.android.chrome', android, UpdateSource.website),
    ('com.aurora.store', android, UpdateSource.website),
    (null, android, UpdateSource.website),
    ('com.apple', ios, UpdateSource.appStore),
    ('com.apple.testflight', ios, null),
    ('com.apple.simulator', ios, null),
    (null, ios, null),
    ('com.android.vending', ios, null),
    ('com.apple', android, UpdateSource.website),
  ]) {
    test('installed by $installer, offering $offered, checks $expected', () {
      expect(updateSourceFor(installer, offered), expected);
    });
  }
}
