import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/auth_browser.dart';
import 'package:zuno/core/matrix/auth_error_message.dart';
import 'package:zuno/core/matrix/registration_support.dart';
import 'package:zuno/core/matrix/server_choice.dart';
import 'package:zuno/core/matrix/typed_server_answers.dart';
import 'package:zuno/core/network/app_http_overrides.dart';

import '../../helpers/uia_challenge.dart';

MatrixException matrixError(String code, String message) =>
    MatrixException.fromJson({'errcode': code, 'error': message});

void main() {
  group('login', () {
    test('a refused password reads as an answer, not a protocol string', () {
      final message = loginErrorMessage(
        englishLocalizations,
        matrixError('M_FORBIDDEN', 'Invalid username or password'),
      );

      expect(message, 'Wrong username or password');
      expect(message, isNot(contains('M_FORBIDDEN')));
    });

    test('a deactivated account says so', () {
      expect(
        loginErrorMessage(
          englishLocalizations,
          matrixError('M_USER_DEACTIVATED', 'deactivated'),
        ),
        'This account is deactivated',
      );
    });

    test('rate limiting says to wait', () {
      expect(
        loginErrorMessage(
          englishLocalizations,
          matrixError('M_LIMIT_EXCEEDED', 'Too many requests'),
        ),
        contains('Wait a moment'),
      );
    });

    test('a refusal of what was typed is an answer, not a failure', () {
      for (final code in [
        'M_FORBIDDEN',
        'M_USER_DEACTIVATED',
        'M_LIMIT_EXCEEDED',
      ]) {
        expect(isLoginRefusal(matrixError(code, 'no')), isTrue, reason: code);
      }
    });

    test('anything else a sign-in meets is a failure', () {
      for (final error in <Object>[
        matrixError('M_UNKNOWN', 'something odd happened'),
        const SocketException('failed'),
        StateError('Bad state: no element'),
      ]) {
        expect(isLoginRefusal(error), isFalse, reason: '$error');
      }
    });

    test('an unreachable server is a different problem from a password', () {
      final message = loginErrorMessage(
        englishLocalizations,
        const SocketException('failed'),
      );

      expect(message, contains('Cannot connect'));
      expect(message.toLowerCase(), isNot(contains('password')));
    });

    test(
      "an unknown refusal keeps the server's own message, as a sentence",
      () {
        expect(
          loginErrorMessage(
            englishLocalizations,
            matrixError('M_UNKNOWN', 'something odd happened'),
          ),
          'Something odd happened',
        );
      },
    );

    test('an empty message still says something', () {
      expect(
        loginErrorMessage(englishLocalizations, matrixError('M_UNKNOWN', '')),
        'Something went wrong. Try again.',
      );
    });

    test('an error nobody planned for never shows its own text', () {
      for (final message in [
        loginErrorMessage(
          englishLocalizations,
          StateError('Bad state: no element'),
        ),
        registrationErrorMessage(
          englishLocalizations,
          StateError('Bad state: no element'),
        ),
        deactivateAccountErrorMessage(
          englishLocalizations,
          StateError('Bad state: no element'),
        ),
      ]) {
        expect(message, 'Something went wrong. Try again.');
      }
    });

    test("a server's message is cut to its first line", () {
      expect(
        loginErrorMessage(
          englishLocalizations,
          matrixError('M_UNKNOWN', 'first line\nsecond line'),
        ),
        'First line',
      );
    });

    test('a rate limit that names its wait passes it on', () {
      MatrixException limited(int ms) => MatrixException.fromJson({
        'errcode': 'M_LIMIT_EXCEEDED',
        'error': 'Too many requests',
        'retry_after_ms': ms,
      });

      expect(
        loginErrorMessage(englishLocalizations, limited(30000)),
        'Too many attempts. Try again in 30 seconds.',
      );
      expect(
        registrationErrorMessage(englishLocalizations, limited(1000)),
        'Too many attempts. Try again in 1 second.',
      );
      expect(
        loginErrorMessage(englishLocalizations, limited(60000)),
        'Too many attempts. Try again in 1 minute.',
      );
      expect(
        loginErrorMessage(englishLocalizations, limited(90000)),
        'Too many attempts. Try again in 2 minutes.',
      );
    });
  });

  group('retryWaitFor', () {
    MatrixException limited(Object? ms) => MatrixException.fromJson({
      'errcode': 'M_LIMIT_EXCEEDED',
      'error': 'Too many requests',
      'retry_after_ms': ?ms,
    });

    test('reads the wait off a rate limit', () {
      expect(retryWaitFor(limited(30000)), const Duration(seconds: 30));
    });

    test('a rate limit with no wait, or a useless one, has none', () {
      expect(retryWaitFor(limited(null)), isNull);
      expect(retryWaitFor(limited(0)), isNull);
      expect(retryWaitFor(limited(-5)), isNull);
    });

    test('falls back to the Retry-After header the spec now prefers', () {
      MatrixException limitedBy(String header) => MatrixException(
        http.Response(
          '{"errcode":"M_LIMIT_EXCEEDED","error":"Too many requests"}',
          429,
          headers: {'retry-after': header},
        ),
      );

      expect(retryWaitFor(limitedBy('12')), const Duration(seconds: 12));
      expect(retryWaitFor(limitedBy('soon')), isNull);
      expect(retryWaitFor(limitedBy('0')), isNull);
    });

    test('an absurd wait is capped', () {
      expect(retryWaitFor(limited(86400000)), maxRetryWait);
    });

    test('nothing else carries a wait', () {
      expect(retryWaitFor(matrixError('M_FORBIDDEN', 'no')), isNull);
      expect(retryWaitFor(const SocketException('down')), isNull);
    });

    test('a rate limit without Matrix JSON waits for its Retry-After', () {
      const thirty = Duration(seconds: 30);

      expect(
        retryWaitFor(const ServerAnswerFailed(429, retryAfter: thirty)),
        thirty,
      );
      expect(retryWaitFor(const ServerAnswerFailed(429)), isNull);
      expect(
        retryWaitFor(const ServerAnswerFailed(503, retryAfter: thirty)),
        isNull,
      );
      expect(
        retryWaitFor(
          const ServerAnswerFailed(429, retryAfter: Duration(days: 1)),
        ),
        maxRetryWait,
      );
    });
  });

  group('a rate limit without Matrix JSON', () {
    const limited = ServerAnswerFailed(429, retryAfter: Duration(seconds: 30));

    test('reads like the server\'s own wherever it lands', () {
      for (final message in [
        loginErrorMessage(englishLocalizations, limited),
        registrationErrorMessage(englishLocalizations, limited),
        deactivateAccountErrorMessage(englishLocalizations, limited),
        homeserverErrorMessage(englishLocalizations, limited),
      ]) {
        expect(message, 'Too many attempts. Try again in 30 seconds.');
      }
      expect(
        loginErrorMessage(englishLocalizations, const ServerAnswerFailed(429)),
        'Too many attempts. Wait a moment and try again.',
      );
    });

    test('is an answer, not a failure', () {
      expect(isLoginRefusal(limited), isTrue);
      expect(isRegistrationRefusal(limited), isTrue);
    });

    test('a server failure is the same unreachable copy and not reported', () {
      const down = ServerAnswerFailed(502);
      for (final message in [
        loginErrorMessage(englishLocalizations, down),
        registrationErrorMessage(englishLocalizations, down),
      ]) {
        expect(message, englishLocalizations.matrixHomeserverUnreachable);
      }
      expect(isLoginRefusal(down), isTrue);
      expect(isRegistrationRefusal(down), isTrue);
      expect(isLoginRefusal(const ServerAnswerFailed(404)), isFalse);
    });
  });

  group('changing the password', () {
    String message(Object error) =>
        changePasswordErrorMessage(englishLocalizations, error);

    test('a wrong current password says so', () {
      expect(
        message(matrixError('M_FORBIDDEN', 'Invalid password')),
        'Wrong password.',
      );
    });

    test("the server's password policy refusal asks for a stronger "
        'password', () {
      for (final code in ['M_WEAK_PASSWORD', 'M_PASSWORD_TOO_SHORT']) {
        expect(
          message(matrixError(code, 'no')),
          'Your server needs a stronger password. Try a longer one.',
          reason: code,
        );
      }
    });

    test('a server failure says the server cannot be reached', () {
      expect(
        message(const ServerAnswerFailed(502)),
        englishLocalizations.matrixHomeserverUnreachable,
      );
    });

    test('anything else says the password was not changed', () {
      expect(
        message(matrixError('M_UNKNOWN', 'something odd happened')),
        'Password not changed. Try again.',
      );
    });

    test('refusals are answers, anything else is a failure', () {
      for (final error in <Object>[
        matrixError('M_FORBIDDEN', 'no'),
        matrixError('M_WEAK_PASSWORD', 'no'),
        matrixError('M_PASSWORD_NO_DIGIT', 'no'),
        matrixError('M_LIMIT_EXCEEDED', 'no'),
        const ServerAnswerFailed(502),
      ]) {
        expect(isChangePasswordRefusal(error), isTrue, reason: '$error');
      }
      expect(isChangePasswordRefusal(matrixError('M_UNKNOWN', 'no')), isFalse);
    });
  });

  group('registration', () {
    test('a taken username says so', () {
      expect(
        registrationErrorMessage(
          englishLocalizations,
          matrixError('M_USER_IN_USE', 'User ID already taken.'),
        ),
        'That username is already taken',
      );
    });

    test('a rejected username says so', () {
      expect(
        registrationErrorMessage(
          englishLocalizations,
          matrixError('M_INVALID_USERNAME', 'nope'),
        ),
        'That username is not allowed',
      );
    });

    test("the server's password policy refusal asks for a stronger "
        'password', () {
      for (final code in ['M_WEAK_PASSWORD', 'M_PASSWORD_TOO_SHORT']) {
        expect(
          registrationErrorMessage(
            englishLocalizations,
            matrixError(code, 'password must be at least 12 characters'),
          ),
          'Your server needs a stronger password. Try a longer one.',
          reason: code,
        );
      }
    });

    test('a refused sign-up code says the code is the problem', () {
      expect(
        registrationErrorMessage(
          englishLocalizations,
          const RegistrationCodeRefusedException(),
        ),
        'That code is not valid or has expired.',
      );
    });

    test('a refusal of what was typed is an answer, not a failure', () {
      for (final code in [
        'M_USER_IN_USE',
        'M_INVALID_USERNAME',
        'M_EXCLUSIVE',
        'M_WEAK_PASSWORD',
        'M_PASSWORD_TOO_SHORT',
        'M_LIMIT_EXCEEDED',
      ]) {
        expect(
          isRegistrationRefusal(matrixError(code, 'no')),
          isTrue,
          reason: code,
        );
      }
    });

    test('anything else a sign-up meets is a failure', () {
      for (final error in <Object>[
        matrixError('M_UNKNOWN', 'something odd happened'),
        uiaPasswordChallenge(stages: ['m.login.recaptcha']),
        StateError('Bad state: no element'),
      ]) {
        expect(isRegistrationRefusal(error), isFalse, reason: '$error');
      }
    });
  });

  group('homeserverErrorMessage', () {
    test("can't reach it points at the address, not just the connection", () {
      final message = homeserverErrorMessage(
        englishLocalizations,
        const SocketException('Failed host lookup'),
      );

      expect(message, contains('address'));
      expect(message, isNot(contains('SocketException')));
    });

    for (final (label, error) in <(String, Object)>[
      (
        'a server that answers but is not a homeserver',
        const ServerAnswerFailed(404),
      ),
      ('a non-JSON response', const FormatException('Unexpected character')),
      ('a JSON response of the wrong shape', TypeError()),
    ]) {
      test('$label is a wrong-address answer, not a dump', () {
        expect(
          homeserverErrorMessage(englishLocalizations, error),
          'That address is not a server Zuno can use. Check it.',
        );
      });
    }

    test('whatever the address turns out to be is an answer, not a '
        'failure', () {
      for (final error in <Object>[
        const ServerAnswerFailed(404),
        const FormatException('Unexpected character'),
        TypeError(),
        matrixError('M_UNRECOGNIZED', 'Unrecognized request'),
        matrixError('M_LIMIT_EXCEEDED', 'Too many requests'),
        const UnsupportedSignInException(),
        const ServerAnswerFailed(429),
        const ServerAnswerFailed(502),
        const SocketException('Failed host lookup'),
      ]) {
        expect(homeserverProblem(error).reported, isFalse, reason: '$error');
      }
    });

    test('an error nobody planned for is a failure, and still points at '
        'the address', () {
      final error = StateError('Bad state: no element');

      expect(homeserverProblem(error).reported, isTrue);
      expect(
        homeserverErrorMessage(englishLocalizations, error),
        'That address is not a server Zuno can use. Check it.',
      );
    });

    test('a server that would take a sign-in over http says it is not '
        'secure, not that it cannot be reached', () {
      final error = CleartextRefusedException(
        Uri.parse('http://matrix.example.org/_matrix/client/versions'),
      );

      expect(
        homeserverErrorMessage(englishLocalizations, error),
        'That server uses http, which is not secure. Zuno connects only '
        'over https.',
      );
      expect(homeserverProblem(error).reported, isFalse);
    });

    test('a server answering with a server error is unreachable, any other '
        'refusal is not a server', () {
      expect(
        homeserverProblem(const ServerAnswerFailed(502)),
        HomeserverProblem.unreachable,
      );
      expect(
        homeserverProblem(const ServerAnswerFailed(403)),
        HomeserverProblem.notAServer,
      );
      expect(
        const ServerAnswerFailed(502).toString(),
        'ServerAnswerFailed(502)',
      );
    });

    test('a rate-limited check says to wait', () {
      expect(
        homeserverProblem(const ServerAnswerFailed(429)),
        HomeserverProblem.rateLimited,
      );
      expect(
        homeserverErrorMessage(
          englishLocalizations,
          const ServerAnswerFailed(429),
        ),
        'Too many attempts. Wait a moment and try again.',
      );
    });

    test('a rate limit refusal during the check says how long to wait', () {
      final error = MatrixException.fromJson({
        'errcode': 'M_LIMIT_EXCEEDED',
        'error': 'Too many requests',
        'retry_after_ms': 30000,
      });

      expect(homeserverProblem(error), HomeserverProblem.rateLimited);
      expect(
        homeserverErrorMessage(englishLocalizations, error),
        'Too many attempts. Try again in 30 seconds.',
      );
    });

    test('a server with no usable sign-in says so', () {
      const error = UnsupportedSignInException();

      expect(homeserverProblem(error), HomeserverProblem.unsupportedSignIn);
      expect(
        homeserverErrorMessage(englishLocalizations, error),
        'Zuno cannot sign in to that server.',
      );
    });

    test('never multi-line — this field renders every line it is given', () {
      for (final error in <Object>[
        const SocketException('nope'),
        const ServerAnswerFailed(404),
        const FormatException('Unexpected character (at character 1)\nx\n^'),
      ]) {
        expect(
          homeserverErrorMessage(englishLocalizations, error),
          isNot(contains('\n')),
        );
      }
    });
  });

  group('deactivateAccountErrorMessage', () {
    test('a wrong password re-entered for UIA says so, not "M_FORBIDDEN"', () {
      final message = deactivateAccountErrorMessage(
        englishLocalizations,
        matrixError('M_FORBIDDEN', 'Invalid password'),
      );

      expect(message, 'Wrong password.');
      expect(message, isNot(contains('M_FORBIDDEN')));
    });

    test('an unreachable server is a different problem from a password', () {
      final message = deactivateAccountErrorMessage(
        englishLocalizations,
        const SocketException('failed'),
      );

      expect(message, contains('Cannot connect'));
      expect(message.toLowerCase(), isNot(contains('password')));
    });

    test(
      "an unknown refusal keeps the server's own message, as a sentence",
      () {
        expect(
          deactivateAccountErrorMessage(
            englishLocalizations,
            matrixError('M_UNKNOWN', 'something odd happened'),
          ),
          'Something odd happened',
        );
      },
    );
  });

  group('password prompts', () {
    test('a refused password is an answer, not a failure', () {
      expect(
        isPasswordRefusal(matrixError('M_FORBIDDEN', 'Invalid password')),
        isTrue,
      );
    });

    test('anything else a password prompt meets is a failure', () {
      for (final error in <Object>[
        matrixError('M_LIMIT_EXCEEDED', 'Too many requests'),
        matrixError('M_USER_DEACTIVATED', 'deactivated'),
        const SocketException('failed'),
      ]) {
        expect(isPasswordRefusal(error), isFalse, reason: '$error');
      }
    });
  });

  group('oauthSignInErrorMessage', () {
    String message(Object error) => oauthSignInErrorMessage(
      englishLocalizations,
      error,
      server: 'zuno.chat',
    );

    test('no browser says Zuno needs one', () {
      expect(
        message(const AuthBrowserUnavailable()),
        'Zuno needs a web browser to sign in to zuno.chat.',
      );
    });

    test('a connection error is the unreachable line', () {
      expect(
        message(const SocketException('Failed host lookup')),
        englishLocalizations.matrixAuthCannotConnect,
      );
    });

    test('a failed sign-in, an OIDC error and anything else name the '
        'server', () {
      for (final error in <Object>[
        const OAuthSignInFailed('state_mismatch'),
        const OAuthSignInFailed('EUNKNOWN'),
        OidcException(error: 'invalid_grant', errorDescription: null),
        StateError('x'),
      ]) {
        expect(
          message(error),
          'Could not sign in to zuno.chat. Try again.',
          reason: '$error',
        );
      }
    });

    test('a rate limit says to wait, for as long as the server said', () {
      expect(
        message(
          MatrixException.fromJson({
            'errcode': 'M_LIMIT_EXCEEDED',
            'retry_after_ms': 30000,
          }),
        ),
        'Too many attempts. Try again in 30 seconds.',
      );
      expect(
        message(matrixError('M_LIMIT_EXCEEDED', 'Slow down')),
        'Too many attempts. Wait a moment and try again.',
      );
    });

    test('a server error from the server says it cannot be reached', () {
      for (final status in [500, 502, 503]) {
        expect(
          message(ServerAnswerFailed(status)),
          'Cannot reach that server. Check the address and your connection.',
          reason: '$status',
        );
      }
    });

    test('a rate limit without Matrix JSON says to wait, for as long as its '
        'Retry-After said', () {
      expect(
        message(const ServerAnswerFailed(429)),
        'Too many attempts. Wait a moment and try again.',
      );
      expect(
        message(
          const ServerAnswerFailed(429, retryAfter: Duration(seconds: 30)),
        ),
        'Too many attempts. Try again in 30 seconds.',
      );
    });

    test('any other server answer names the server', () {
      for (final error in const [
        ServerAnswerFailed(400, oauthError: 'invalid_client_metadata'),
        ServerAnswerFailed(404),
      ]) {
        expect(
          message(error),
          'Could not sign in to zuno.chat. Try again.',
          reason: '$error',
        );
      }
    });

    test('a server error and a rate limit without Matrix JSON are expected; '
        'any other server answer is not', () {
      for (final error in const [
        ServerAnswerFailed(500),
        ServerAnswerFailed(503),
        ServerAnswerFailed(429),
      ]) {
        expect(isExpectedOAuthSignInFailure(error), isTrue, reason: '$error');
      }
      for (final error in const [
        ServerAnswerFailed(400, oauthError: 'invalid_client_metadata'),
        ServerAnswerFailed(404),
      ]) {
        expect(isExpectedOAuthSignInFailure(error), isFalse, reason: '$error');
      }
    });

    test('a cancel, a missing browser, no connection and a rate limit are '
        'expected; a failed sign-in and anything else are not', () {
      expect(
        isExpectedOAuthSignInFailure(const OAuthSignInCancelled()),
        isTrue,
      );
      expect(
        isExpectedOAuthSignInFailure(const AuthBrowserUnavailable()),
        isTrue,
      );
      expect(
        isExpectedOAuthSignInFailure(http.ClientException('offline')),
        isTrue,
      );
      expect(
        isExpectedOAuthSignInFailure(matrixError('M_LIMIT_EXCEEDED', 'x')),
        isTrue,
      );
      expect(
        isExpectedOAuthSignInFailure(const OAuthSignInFailed('server_error')),
        isFalse,
      );
      expect(isExpectedOAuthSignInFailure(StateError('x')), isFalse);
    });

    test('only a cancel is a cancel', () {
      expect(isOAuthSignInCancel(const OAuthSignInCancelled()), isTrue);
      expect(isOAuthSignInCancel(const OAuthSignInFailed('x')), isFalse);
      expect(isOAuthSignInCancel(StateError('x')), isFalse);
    });
  });
}
