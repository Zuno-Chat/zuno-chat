import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

typedef VodozemacInit = Future<void> Function();

bool _initialized = false;
Future<void>? _inFlight;

Future<void> ensureVodozemacInitialized({VodozemacInit init = vod.init}) async {
  if (_initialized) return;
  final existing = _inFlight;
  if (existing != null) {
    await existing;
    return;
  }
  final attempt = init();
  _inFlight = attempt;
  try {
    await attempt;
    _initialized = true;
  } finally {
    _inFlight = null;
  }
}

@visibleForTesting
void resetVodozemacInitForTest() {
  _initialized = false;
  _inFlight = null;
}
