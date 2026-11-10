import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/pushers/push_gateway.dart';

void main() {
  test('every build sends through Zuno\'s gateway', () {
    expect(
      zunoPushGateway,
      Uri.parse('https://push.zuno.chat/_matrix/push/v1/notify'),
    );
  });
}
