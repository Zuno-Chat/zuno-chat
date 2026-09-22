import 'package:matrix/matrix.dart';

bool isUndecryptableEvent(Event event) => event.type == EventTypes.Encrypted;
