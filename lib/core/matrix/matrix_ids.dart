import 'package:matrix/matrix.dart';

const matrixLocalpartChars = r'a-z0-9._=/+-';

String withoutServer(String matrixId) {
  final sigil = matrixId.sigil;
  final localpart = matrixId.localpart;
  if (sigil == null || localpart == null) return matrixId;
  return '$sigil$localpart';
}
