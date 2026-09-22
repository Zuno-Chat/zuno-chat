import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/restore_key_backup.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  test('reports failure, without throwing, when there is no encryption',
      () async {
    final client = buildTestClient();
    expect(client.encryption, isNull);

    await expectLater(restoreKeyBackupFromRecovery(client), completes);
    expect(await restoreKeyBackupFromRecovery(client), isFalse);
  });

  test('a homeserver that has no key backup is a failure, not a crash',
      () async {
    final client = buildTestClient(userId: '@a:x');

    await expectLater(restoreKeyBackupFromRecovery(client), completes);
    expect(await restoreKeyBackupFromRecovery(client), isFalse);
  });
}
