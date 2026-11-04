import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:vodozemac/src/generated/frb_generated.dart';

class _Sha256OnlyApi implements RustLibApi {
  @override
  Uint8List crateBindingsSha256({required List<int> input}) =>
      Uint8List.fromList(crypto.sha256.convert(input).bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} needs the real library');
}

var _installed = false;

void installSha256OnlyVodozemac() {
  RustLib.initMock(api: _Sha256OnlyApi());
  _installed = true;
}

void removeSha256OnlyVodozemac() {
  if (!_installed) return;
  _installed = false;
  RustLib.dispose();
}
