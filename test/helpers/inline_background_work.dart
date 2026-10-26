import 'dart:async';
import 'dart:isolate';

Future<R> runInline<R>(FutureOr<R> Function() work, {String? debugName}) =>
    Future.sync(() {
      _mustReachAnIsolate(work);
      return work();
    }).then((result) {
      _mustReachAnIsolate(result);
      return result;
    });

void _mustReachAnIsolate(Object? message) {
  final port = RawReceivePort();
  try {
    port.sendPort.send(message);
  } finally {
    port.close();
  }
}
