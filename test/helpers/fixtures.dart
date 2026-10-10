import 'dart:convert';
import 'dart:io';

import 'package:zuno/core/security/recovery_code.dart';

RecoveryWordlist shippedRecoveryWordlist() => RecoveryWordlist.parse(
  File('assets/wordlist/recovery_words.txt').readAsStringSync(),
);

Map<String, dynamic> pushFixture(String name) =>
    jsonDecode(File('test/fixtures/push/$name').readAsStringSync())
        as Map<String, dynamic>;

String hexOf(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
