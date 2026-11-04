import 'package:matrix/matrix.dart';

const forwardedKey = 'im.zuno.forwarded';

bool isForwarded(Event event) => event.content[forwardedKey] == true;
