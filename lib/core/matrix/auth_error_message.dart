import 'dart:math' as math;

import 'package:matrix/matrix.dart';

import '../errors/connection_error.dart';
import '../l10n/l10n.dart';
import '../network/app_http_overrides.dart';
import 'registration_code_request.dart';
import 'registration_support.dart';

String loginErrorMessage(AppLocalizations l10n, Object error) {
  final network = _networkErrorMessage(l10n, error);
  if (network != null) return network;
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_FORBIDDEN => l10n.matrixAuthWrongCredentials,
      MatrixError.M_USER_DEACTIVATED => l10n.matrixAuthDeactivated,
      MatrixError.M_LIMIT_EXCEEDED => _rateLimitMessage(l10n, error),
      MatrixError.M_UNKNOWN_TOKEN => l10n.matrixAuthSignedOut,
      _ => _sentence(l10n, error.errorMessage),
    };
  }
  return l10n.matrixAuthUnexpected;
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

String registrationErrorMessage(AppLocalizations l10n, Object error) {
  if (error is RegistrationCodeRefusedException) {
    return l10n.matrixAuthCodeInvalid;
  }
  final network = _networkErrorMessage(l10n, error);
  if (network != null) return network;
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_USER_IN_USE => l10n.matrixAuthUsernameTaken,
      MatrixError.M_INVALID_USERNAME ||
      MatrixError.M_EXCLUSIVE => l10n.matrixAuthUsernameNotAllowed,
      MatrixError.M_LIMIT_EXCEEDED => _rateLimitMessage(l10n, error),
      _ => _sentence(l10n, error.errorMessage),
    };
  }
  return l10n.matrixAuthUnexpected;
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

String deactivateAccountErrorMessage(AppLocalizations l10n, Object error) {
  final network = _networkErrorMessage(l10n, error);
  if (network != null) return network;
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_FORBIDDEN => l10n.commonWrongPassword,
      MatrixError.M_LIMIT_EXCEEDED => _rateLimitMessage(l10n, error),
      _ => _sentence(l10n, error.errorMessage),
    };
  }
  return l10n.matrixAuthUnexpected;
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

String _rateLimitMessage(AppLocalizations l10n, MatrixException error) {
  final wait = retryWaitFor(error);
  if (wait == null) return l10n.matrixAuthRateLimited;
  final seconds = (wait.inMilliseconds / 1000).ceil();
  return seconds < 60
      ? l10n.matrixAuthRateLimitedSeconds(seconds)
      : l10n.matrixAuthRateLimitedMinutes((seconds / 60).ceil());
}

String? _networkErrorMessage(AppLocalizations l10n, Object error) {
  if (isConnectionError(error)) return l10n.matrixAuthCannotConnect;
  return null;
}

String _sentence(AppLocalizations l10n, String message) {
  final line = message.trim().split('\n').first.trim();
  if (line.isEmpty) return l10n.matrixAuthUnexpected;
  return line[0].toUpperCase() + line.substring(1);
}

enum HomeserverProblem {
  unreachable,
  insecure,
  noPasswordSignIn,
  refused,
  notAServer,
  unexpected;

  bool get reported => this == unexpected;
}

HomeserverProblem homeserverProblem(Object error) {
  if (error is CleartextRefusedException) return HomeserverProblem.insecure;
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

String homeserverErrorMessage(AppLocalizations l10n, Object error) =>
    switch (homeserverProblem(error)) {
      HomeserverProblem.unreachable => l10n.matrixHomeserverUnreachable,
      HomeserverProblem.insecure => l10n.matrixHomeserverInsecure,
      HomeserverProblem.noPasswordSignIn => l10n.matrixHomeserverNoPassword,
      HomeserverProblem.refused => _sentence(
        l10n,
        (error as MatrixException).errorMessage,
      ),
      HomeserverProblem.notAServer ||
      HomeserverProblem.unexpected => l10n.matrixHomeserverNotAServer,
    };

String? registrationCodeErrorMessage(
  AppLocalizations l10n,
  RegistrationCodeOutcome outcome,
) {
  return switch (outcome) {
    RegistrationCodeOutcome.sent => null,
    RegistrationCodeOutcome.invalidEmail => l10n.matrixCodeInvalidEmail,
    RegistrationCodeOutcome.rateLimited => l10n.matrixCodeRateLimited,
    RegistrationCodeOutcome.unavailable => l10n.matrixCodeUnavailable,
    RegistrationCodeOutcome.serverError => l10n.matrixCodeServerError,
    RegistrationCodeOutcome.offline => l10n.matrixCodeOffline,
  };
}
