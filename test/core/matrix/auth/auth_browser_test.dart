import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/auth/auth_browser.dart';

const _channel = MethodChannel('flutter_web_auth_2');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  void answer(Future<Object?> Function(MethodCall call) handler) {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
          calls.add(call);
          if (call.method != 'authenticate') return Future.value();
          return handler(call);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
  }

  final authorization = Uri.parse('https://auth.example.org/authorize?x=1');

  test('returns the callback', () async {
    answer((_) async => 'chat.zuno:/oauth?code=c&state=s');

    final callback = await systemAuthBrowser(authorization, 'chat.zuno');

    expect(callback, Uri.parse('chat.zuno:/oauth?code=c&state=s'));
    final call = calls.singleWhere((call) => call.method == 'authenticate');
    expect(call.arguments['url'], authorization.toString());
    expect(call.arguments['callbackUrlScheme'], 'chat.zuno');
    expect(call.arguments['options']['preferEphemeral'], isTrue);
  });

  test('a malformed callback fails without carrying it', () async {
    answer((_) async => 'chat.zuno://[bad?code=secret&state=s');

    await expectLater(
      systemAuthBrowser(authorization, 'chat.zuno'),
      throwsA(
        isA<OAuthSignInFailed>()
            .having((e) => e.reason, 'reason', 'bad_callback')
            .having((e) => e.toString(), 'text', isNot(contains('secret'))),
      ),
    );
  });

  test('cancel maps to OAuthSignInCancelled', () async {
    answer((_) async => throw PlatformException(code: 'CANCELED'));

    await expectLater(
      systemAuthBrowser(authorization, 'chat.zuno'),
      throwsA(isA<OAuthSignInCancelled>()),
    );
  });

  test('no browser maps to AuthBrowserUnavailable', () async {
    answer((_) async => throw PlatformException(code: 'NO_BROWSER'));

    await expectLater(
      systemAuthBrowser(authorization, 'chat.zuno'),
      throwsA(isA<AuthBrowserUnavailable>()),
    );
  });

  test('other failures map to OAuthSignInFailed', () async {
    for (final code in ['EUNKNOWN', 'FAILED', 'SECURITY_EXCEPTION']) {
      answer((_) async => throw PlatformException(code: code));

      await expectLater(
        systemAuthBrowser(authorization, 'chat.zuno'),
        throwsA(
          isA<OAuthSignInFailed>().having((e) => e.reason, 'reason', code),
        ),
      );
    }
  });

  group('a page shown until it is closed', () {
    final page = Uri.parse('https://auth.example.org/account/');

    test('is shown once and counts as shown when closed', () async {
      final shown = <(Uri, String)>[];

      final result = await showUntilClosed(
        (uri, scheme) async {
          shown.add((uri, scheme));
          throw const OAuthSignInCancelled();
        },
        page,
        callbackScheme: 'chat.zuno',
      );

      expect(result, isTrue);
      expect(shown, [(page, 'chat.zuno')]);
    });

    test('with no browser counts as not shown', () async {
      final result = await showUntilClosed(
        (_, _) async => throw const AuthBrowserUnavailable(),
        page,
        callbackScheme: 'chat.zuno',
      );

      expect(result, isFalse);
    });

    test('passes any other failure on', () async {
      await expectLater(
        showUntilClosed(
          (_, _) async => throw const OAuthSignInFailed('EUNKNOWN'),
          page,
          callbackScheme: 'chat.zuno',
        ),
        throwsA(isA<OAuthSignInFailed>()),
      );
    });
  });

  test('the reason reaches the reports and nothing else does', () {
    expect(
      const OAuthSignInFailed('EUNKNOWN').toString(),
      'OAuthSignInFailed(EUNKNOWN)',
    );
  });
}
