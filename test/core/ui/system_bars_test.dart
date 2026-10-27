import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/system_bars.dart';

import '../../helpers/native_method_calls.dart';

void main() {
  late RecordedMethodCalls platform;

  setUp(() => platform = recordChannel(SystemChannels.platform));

  testWidgets('hiding the bars goes immersive', (tester) async {
    await hideSystemBars();

    expect(platform.argsOf('SystemChrome.setEnabledSystemUIMode'), [
      'SystemUiMode.immersiveSticky',
    ]);
  });

  testWidgets('showing the bars names both bars before going edge to edge, '
      'since Android before 10 ignores edge to edge', (tester) async {
    await showSystemBars();

    expect(platform.methods, [
      'SystemChrome.setEnabledSystemUIOverlays',
      'SystemChrome.setEnabledSystemUIMode',
    ]);
    expect(platform.calls.first.arguments, [
      'SystemUiOverlay.top',
      'SystemUiOverlay.bottom',
    ]);
    expect(platform.calls.last.arguments, 'SystemUiMode.edgeToEdge');
  });
}
