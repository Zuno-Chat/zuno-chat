import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';

void main() {
  test('unitsMembers says 1 member and many members', () {
    expect(englishLocalizations.unitsMembers(1), '1 member');
    expect(englishLocalizations.unitsMembers(2), '2 members');
    expect(englishLocalizations.unitsMembers(0), '0 members');
    expect(englishLocalizations.unitsMembers(120), '120 members');
  });
}
