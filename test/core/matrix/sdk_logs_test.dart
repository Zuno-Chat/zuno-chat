import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/sdk_logs.dart';

import '../../helpers/recording_sentry.dart';

void main() {
  final transport = useRecordingSentry();

  tearDown(() => Logs().onLog = null);

  test('the SDK keeps no history of what it logs', () {
    handleSdkLogs();

    Logs().v('Decrypted to_device event is: {"geo_uri":"geo:1,2"}');
    Logs().w('a warning');

    expect(Logs().outputEvents, isEmpty);
  });

  test('an SDK error is reported under its title', () async {
    handleSdkLogs();

    Logs().e('[Key Manager] Error uploading room keys', StateError('x'));
    Logs().wtf('Unable to migrate OLM sessions!');
    await pumpEventQueue();

    expect(transport.events.map((e) => e.tags?['caught']), [
      'sdk: [Key Manager] Error uploading room keys',
      'sdk: Unable to migrate OLM sessions!',
    ]);
    expect(transport.events.last.throwable, isA<SdkLoggedError>());
  });

  test('an SDK warning, info or debug line is never reported', () async {
    handleSdkLogs();

    Logs().w('a warning', StateError('w'));
    Logs().i('info');
    Logs().d('debug', StateError('d'));
    await pumpEventQueue();

    expect(transport.events, isEmpty);
  });

  test('an SDK error carries its title as the message', () async {
    handleSdkLogs();

    Logs().e('[Key Manager] Error uploading room keys', StateError('x'));
    await pumpEventQueue();

    expect(
      transport.sentEvent.message?.formatted,
      '[Key Manager] Error uploading room keys',
    );
  });

  test('an error the SDK hands on to Zuno is left to Zuno', () async {
    handleSdkLogs();

    Logs().wtf('Client initialization failed', StateError('x'));
    Logs().e('Logout failed', StateError('x'));
    Logs().e('[Bootstrapping] Error setting up cross signing', StateError('x'));
    await pumpEventQueue();

    expect(transport.events, isEmpty);
  });

  test('an SDK error is labelled by where the SDK logged it', () {
    final stack = StackTrace.fromString(
      '#0      Logs.e (package:matrix/matrix_api_lite/utils/logs.dart:57:7)\n'
      '#1      stopMediaStream (package:matrix/src/voip/utils/stream_helper.dart:17:16)\n'
      '#2      main (package:zuno/main.dart:12:3)',
    );

    expect(sdkCallSite(stack), 'src/voip/utils/stream_helper.dart:17');
    expect(
      sdkCallSite(
        StackTrace.fromString('#0 main (package:zuno/main.dart:1:1)'),
      ),
      isNull,
    );
  });
}
