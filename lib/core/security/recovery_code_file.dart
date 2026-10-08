import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../files/picked_file.dart';

const recoveryCodeFileName = 'zuno-recovery-code.txt';

const _maxRecoveryCodeFileBytes = 1024;

final _controlCharacter = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

Uint8List encodeRecoveryCodeFile(String code) =>
    Uint8List.fromList(utf8.encode('$code\n'));

String? decodeRecoveryCodeFile(Uint8List bytes) {
  if (bytes.length > _maxRecoveryCodeFileBytes) return null;
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return null;
  }
  if (_controlCharacter.hasMatch(text)) return null;
  final code = text.trim();
  return code.isEmpty ? null : code;
}

Future<String?> readPickedRecoveryCodeFile(
  PlatformFile file, {
  List<Directory>? temporaryRoots,
}) async {
  try {
    final length = file.lengthSync() ?? await file.length();
    if (length > _maxRecoveryCodeFileBytes) return null;
    return decodeRecoveryCodeFile(await file.readAsBytes());
  } finally {
    await discardPickedCopy(file, temporaryRoots: temporaryRoots);
  }
}
