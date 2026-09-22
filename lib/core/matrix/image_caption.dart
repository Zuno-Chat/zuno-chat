import 'package:matrix/matrix.dart';

String? imageCaption(Event event) {
  final filename = event.content.tryGet<String>('filename');
  final body = event.body;
  if (filename == null || body.isEmpty || body == filename) return null;
  return body;
}
