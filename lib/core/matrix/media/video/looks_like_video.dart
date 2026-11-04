import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as p;

bool looksLikeVideo(XFile file) {
  final mimeType = file.mimeType;
  if (mimeType != null) return mimeType.startsWith('video/');
  return const {
    '.mp4',
    '.mov',
    '.m4v',
    '.3gp',
    '.3g2',
    '.mkv',
    '.webm',
    '.avi',
    '.wmv',
  }.contains(p.extension(file.path).toLowerCase());
}
