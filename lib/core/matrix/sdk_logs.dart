import 'package:matrix/matrix.dart';

void keepNoSdkLogHistory() {
  Logs().onLog = (_) => Logs().outputEvents.clear();
}
