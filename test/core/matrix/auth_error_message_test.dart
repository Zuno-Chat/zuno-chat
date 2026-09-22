import 'dart:io' show CertificateException, SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/auth_error_message.dart';
import 'package:zuno/core/matrix/registration_code_request.dart';
import 'package:zuno/core/matrix/registration_support.dart';

MatrixException matrixError(String code, String message) =>
    MatrixException.fromJson({'errcode': code, 'error': message});

void main() {
  group('login', () {
    test('a refused password reads as an answer, not a protocol string', () {
      final message = loginErrorMessage(
        matrixError('M_FORBIDDEN', 'Invalid username or password'),
      );

      expect(message, 'Wrong username or password');
      expect(message, isNot(contains('M_FORBIDDEN')));
    });

    test('a deactivated account says so', () {
      expect(
        loginErrorMessage(matrixError('M_USER_DEACTIVATED', 'deactivated')),
        'This account is deactivated',
      );
    });

    test('rate limiting says to wait', () {
      expect(
        loginErrorMessage(matrixError('M_LIMIT_EXCEEDED', 'Too many requests')),
        contains('Wait a moment'),
      );
    });

    test('an unreachable server is a different problem from a password', () {
      final message = loginErrorMessage(const SocketException('failed'));

      expect(message, contains('Cannot connect'));
      expect(message.toLowerCase(), isNot(contains('password')));
    });

    test(
      "an unknown refusal keeps the server's own message, as a sentence",
      () {
        expect(
          loginErrorMessage(matrixError('M_UNKNOWN', 'something odd happened')),
          'Something odd happened',
        );
      },
    );

    test('an empty message still says something', () {
      expect(
        loginErrorMessage(matrixError('M_UNKNOWN', '')),
        'Something went wrong. Try again.',
      );
    });

    test('a certificate failure is a connection problem, not a dump', () {
      final message = loginErrorMessage(
        const CertificateException('CERTIFICATE_VERIFY_FAILED'),
      );

      expect(message, contains('Cannot connect'));
      expect(message, isNot(contains('CERTIFICATE')));
    });

    test('an error nobody planned for never shows its own text', () {
      for (final message in [
        loginErrorMessage(StateError('Bad state: no element')),
        registrationErrorMessage(StateError('Bad state: no element')),
        deactivateAccountErrorMessage(StateError('Bad state: no element')),
      ]) {
        expect(message, 'Something went wrong. Try again.');
      }
    });

    test("a server's message is cut to its first line", () {
      expect(
        loginErrorMessage(matrixError('M_UNKNOWN', 'first line\nsecond line')),
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
        loginErrorMessage(limited(30000)),
        'Too many attempts. Try again in 30 seconds.',
      );
      expect(
        registrationErrorMessage(limited(1000)),
        'Too many attempts. Try again in 1 second.',
      );
      expect(
        loginErrorMessage(limited(90000)),
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
  });

  group('registration', () {
    test('a taken username says so', () {
      expect(
        registrationErrorMessage(
          matrixError('M_USER_IN_USE', 'User ID already taken.'),
        ),
        'That username is already taken',
      );
    });

    test('a rejected username says so', () {
      expect(
        registrationErrorMessage(matrixError('M_INVALID_USERNAME', 'nope')),
        'That username is not allowed',
      );
    });

    test("a password policy refusal keeps the server's own explanation", () {
      expect(
        registrationErrorMessage(
          matrixError(
            'M_WEAK_PASSWORD',
            'password must be at least 8 characters',
          ),
        ),
        'Password must be at least 8 characters',
      );
    });

    test('a refused sign-up code says the code is the problem', () {
      expect(
        registrationErrorMessage(const RegistrationCodeRefusedException()),
        'That code is not valid or has expired.',
      );
    });
  });

  group('homeserverErrorMessage', () {
    test("can't reach it points at the address, not just the connection", () {
      final message = homeserverErrorMessage(
        const SocketException('Failed host lookup'),
      );

      expect(message, contains('address'));
      expect(message, isNot(contains('SocketException')));
    });

    test('a server that answers but is not a homeserver', () {
      final message = homeserverErrorMessage(Exception('http error response'));

      expect(message, isNot(contains('http error response')));
      expect(message, contains('server'));
    });

    test('a Matrix server with no password login says so', () {
      final message = homeserverErrorMessage(
        BadServerLoginTypesException({'m.login.sso'}, {'m.login.password'}),
      );

      expect(message, contains('password'));
    });

    test(
      'a non-JSON response is a wrong-address answer, not a parser dump',
      () {
        final message = homeserverErrorMessage(
          const FormatException('Unexpected character'),
        );

        expect(message, isNot(contains('FormatException')));
        expect(message, contains('server'));
      },
    );

    test('never multi-line — this field renders every line it is given', () {
      for (final error in <Object>[
        const SocketException('nope'),
        Exception('http error response'),
        const FormatException('Unexpected character (at character 1)\nx\n^'),
      ]) {
        expect(homeserverErrorMessage(error), isNot(contains('\n')));
      }
    });
  });

  group('deactivateAccountErrorMessage', () {
    test('a wrong password re-entered for UIA says so, not "M_FORBIDDEN"', () {
      final message = deactivateAccountErrorMessage(
        matrixError('M_FORBIDDEN', 'Invalid password'),
      );

      expect(message, 'Wrong password.');
      expect(message, isNot(contains('M_FORBIDDEN')));
    });

    test('an unreachable server is a different problem from a password', () {
      final message = deactivateAccountErrorMessage(
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
            matrixError('M_UNKNOWN', 'something odd happened'),
          ),
          'Something odd happened',
        );
      },
    );

    test('an empty message still says something', () {
      expect(
        deactivateAccountErrorMessage(matrixError('M_UNKNOWN', '')),
        'Something went wrong. Try again.',
      );
    });
  });

  group('registrationCodeErrorMessage', () {
    test('a sent code is not an error', () {
      expect(
        registrationCodeErrorMessage(RegistrationCodeOutcome.sent),
        isNull,
      );
    });

    test('each failure says what to do next', () {
      expect(
        registrationCodeErrorMessage(RegistrationCodeOutcome.invalidEmail),
        'That email address does not look right.',
      );
      expect(
        registrationCodeErrorMessage(RegistrationCodeOutcome.rateLimited),
        'Too many code requests. Try again later.',
      );
      expect(
        registrationCodeErrorMessage(RegistrationCodeOutcome.unavailable),
        'New accounts are not being created right now.',
      );
      expect(
        registrationCodeErrorMessage(RegistrationCodeOutcome.serverError),
        'Zuno could not send a code. Try again.',
      );
      expect(
        registrationCodeErrorMessage(RegistrationCodeOutcome.offline),
        'No connection. Try again.',
      );
    });
  });
}
