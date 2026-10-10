import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/unified_push_distributor_names.dart';

void main() {
  test('maps a known distributor id to its display name', () {
    expect(unifiedPushDistributorDisplayName('io.heckel.ntfy'), 'ntfy');
  });

  test('falls back to the raw id for an unknown distributor', () {
    expect(
      unifiedPushDistributorDisplayName('com.example.unknown_distributor'),
      'com.example.unknown_distributor',
    );
  });
}
