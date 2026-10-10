import 'dart:math' as math;

import 'package:matrix/matrix.dart';

import '../errors/connection_error.dart';
import 'registration_code_request.dart';
import 'registration_support.dart';

String loginErrorMessage(Object error) {
  final network = _networkErrorMessage(error);
  if (network != null) return network;
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_FORBIDDEN => 'Wrong username or password',
      MatrixError.M_USER_DEACTIVATED => 'This account is deactivated',
      MatrixError.M_LIMIT_EXCEEDED => _rateLimitMessage(error),
      MatrixError.M_UNKNOWN_TOKEN =>
        'This device was signed out. Sign in again.',
      _ => _sentence(error.errorMessage),
    };
  }
  return _unexpectedErrorMessage;
}

bool isLoginRefusal(Object error) =>
    error is MatrixException &&
    const {
      MatrixError.M_FORBIDDEN,
      MatrixError.M_USER_DEACTIVATED,
      MatrixError.M_LIMIT_EXCEEDED,
    }.contains(error.error);

bool isPasswordRefusal(Object error) =>
    error is MatrixException && error.error == MatrixError.M_FORBIDDEN;

String registrationErrorMessage(Object error) {
  if (error is RegistrationCodeRefusedException) {
    return 'That code is not valid or has expired.';
  }
  final network = _networkErrorMessage(error);
  if (network != null) return network;
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_USER_IN_USE => 'That username is already taken',
      MatrixError.M_INVALID_USERNAME ||
      MatrixError.M_EXCLUSIVE => 'That username is not allowed',
      MatrixError.M_LIMIT_EXCEEDED => _rateLimitMessage(error),
      _ => _sentence(error.errorMessage),
    };
  }
  return _unexpectedErrorMessage;
}

bool isRegistrationRefusal(Object error) =>
    error is MatrixException &&
    const {
      'M_USER_IN_USE',
      'M_INVALID_USERNAME',
      'M_EXCLUSIVE',
      'M_WEAK_PASSWORD',
      'M_LIMIT_EXCEEDED',
    }.contains(error.errcode);

String deactivateAccountErrorMessage(Object error) {
  final network = _networkErrorMessage(error);
  if (network != null) return network;
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_FORBIDDEN => 'Wrong password.',
      MatrixError.M_LIMIT_EXCEEDED => _rateLimitMessage(error),
      _ => _sentence(error.errorMessage),
    };
  }
  return _unexpectedErrorMessage;
}

const maxRetryWait = Duration(minutes: 5);

Duration? retryWaitFor(Object error) {
  if (error is! MatrixException ||
      error.error != MatrixError.M_LIMIT_EXCEEDED) {
    return null;
  }
  final wait = error.retryAfterMs ?? _retryAfterHeaderMs(error);
  if (wait == null || wait <= 0) return null;
  return Duration(milliseconds: math.min(wait, maxRetryWait.inMilliseconds));
}

int? _retryAfterHeaderMs(MatrixException error) {
  final seconds = int.tryParse(error.response?.headers['retry-after'] ?? '');
  return seconds == null ? null : seconds * 1000;
}

String _rateLimitMessage(MatrixException error) {
  final wait = retryWaitFor(error);
  if (wait == null) return 'Too many attempts. Wait a moment and try again.';
  final seconds = (wait.inMilliseconds / 1000).ceil();
  final (count, unit) = seconds < 60
      ? (seconds, 'second')
      : ((seconds / 60).ceil(), 'minute');
  return 'Too many attempts. Try again in $count $unit${count == 1 ? '' : 's'}.';
}

String? _networkErrorMessage(Object error) {
  if (isConnectionError(error)) {
    return 'Cannot connect. Check your connection and try again.';
  }
  return null;
}

const _unexpectedErrorMessage = 'Something went wrong. Try again.';

String _sentence(String message) {
  final line = message.trim().split('\n').first.trim();
  if (line.isEmpty) return _unexpectedErrorMessage;
  return line[0].toUpperCase() + line.substring(1);
}

enum HomeserverProblem {
  unreachable,
  noPasswordSignIn,
  refused,
  notAServer,
  unexpected;

  bool get reported => this == unexpected;
}

HomeserverProblem homeserverProblem(Object error) {
  if (isConnectionError(error)) return HomeserverProblem.unreachable;
  if (error is BadServerLoginTypesException) {
    return HomeserverProblem.noPasswordSignIn;
  }
  if (error is MatrixException) return HomeserverProblem.refused;
  if (error is FormatException ||
      error is TypeError ||
      '$error' == 'Exception: http error response') {
    return HomeserverProblem.notAServer;
  }
  return HomeserverProblem.unexpected;
}

String homeserverErrorMessage(Object error) =>
    switch (homeserverProblem(error)) {
      HomeserverProblem.unreachable =>
        'Cannot reach that server. Check the address and your connection.',
      HomeserverProblem.noPasswordSignIn =>
        'That server does not support signing in with a password.',
      HomeserverProblem.refused => _sentence(
        (error as MatrixException).errorMessage,
      ),
      HomeserverProblem.notAServer || HomeserverProblem.unexpected =>
        'That address is not a server Zuno can use. Check it.',
    };

String? registrationCodeErrorMessage(RegistrationCodeOutcome outcome) {
  return switch (outcome) {
    RegistrationCodeOutcome.sent => null,
    RegistrationCodeOutcome.invalidEmail =>
      'That email address does not look right.',
    RegistrationCodeOutcome.rateLimited =>
      'Too many code requests. Try again later.',
    RegistrationCodeOutcome.unavailable =>
      'New accounts are not being created right now.',
    RegistrationCodeOutcome.serverError =>
      'Zuno could not send a code. Try again.',
    RegistrationCodeOutcome.offline => 'No connection. Try again.',
  };
}
