import 'package:matrix/matrix.dart';
import 'package:zuno_http/zuno_http.dart' show CleartextRefusedException;

import '../../errors/connection_error.dart';
import '../../l10n/l10n.dart';
import '../http/typed_server_answers.dart';
import 'auth_browser.dart';
import 'registration_support.dart';
import 'server_choice.dart';

String loginErrorMessage(AppLocalizations l10n, Object error) {
  if (_serverFailureMessage(l10n, error) case final message?) return message;
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_FORBIDDEN => l10n.matrixAuthWrongCredentials,
      MatrixError.M_USER_DEACTIVATED => l10n.matrixAuthDeactivated,
      MatrixError.M_UNKNOWN_TOKEN => l10n.matrixAuthSignedOut,
      _ => _sentence(l10n, error.errorMessage),
    };
  }
  return l10n.matrixAuthUnexpected;
}

bool isLoginRefusal(Object error) =>
    isRateLimit(error) ||
    isServerError(error) ||
    (error is MatrixException &&
        const {
          MatrixError.M_FORBIDDEN,
          MatrixError.M_USER_DEACTIVATED,
        }.contains(error.error));

bool isPasswordRefusal(Object error) =>
    error is MatrixException && error.error == MatrixError.M_FORBIDDEN;

bool isWeakPasswordRefusal(Object error) =>
    error is MatrixException &&
    (error.errcode == 'M_WEAK_PASSWORD' ||
        error.errcode.startsWith('M_PASSWORD_'));

String changePasswordErrorMessage(AppLocalizations l10n, Object error) {
  if (_serverFailureMessage(l10n, error) case final message?) return message;
  if (isPasswordRefusal(error)) return l10n.commonWrongPassword;
  if (isWeakPasswordRefusal(error)) return l10n.matrixAuthPasswordTooWeak;
  return l10n.settingsChangePasswordFailed;
}

bool isChangePasswordRefusal(Object error) =>
    isRateLimit(error) ||
    isServerError(error) ||
    isPasswordRefusal(error) ||
    isWeakPasswordRefusal(error);

String registrationErrorMessage(AppLocalizations l10n, Object error) {
  if (error is RegistrationCodeRefusedException) {
    return l10n.matrixAuthCodeInvalid;
  }
  if (_serverFailureMessage(l10n, error) case final message?) return message;
  if (isWeakPasswordRefusal(error)) return l10n.matrixAuthPasswordTooWeak;
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_USER_IN_USE => l10n.matrixAuthUsernameTaken,
      MatrixError.M_INVALID_USERNAME ||
      MatrixError.M_EXCLUSIVE => l10n.matrixAuthUsernameNotAllowed,
      _ => _sentence(l10n, error.errorMessage),
    };
  }
  return l10n.matrixAuthUnexpected;
}

bool isRegistrationRefusal(Object error) =>
    isRateLimit(error) ||
    isServerError(error) ||
    isWeakPasswordRefusal(error) ||
    (error is MatrixException &&
        const {
          'M_USER_IN_USE',
          'M_INVALID_USERNAME',
          'M_EXCLUSIVE',
        }.contains(error.errcode));

String deactivateAccountErrorMessage(AppLocalizations l10n, Object error) {
  if (_serverFailureMessage(l10n, error) case final message?) return message;
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_FORBIDDEN => l10n.commonWrongPassword,
      _ => _sentence(l10n, error.errorMessage),
    };
  }
  return l10n.matrixAuthUnexpected;
}

const maxRetryWait = Duration(minutes: 5);

Duration? retryWaitFor(Object error) {
  if (!isRateLimit(error)) return null;
  final wait = switch (error) {
    MatrixException(:final retryAfterMs?) => Duration(
      milliseconds: retryAfterMs,
    ),
    MatrixException(:final response?) => retryAfterIn(response.headers),
    ServerAnswerFailed(:final retryAfter) => retryAfter,
    _ => null,
  };
  if (wait == null || wait <= Duration.zero) return null;
  return wait > maxRetryWait ? maxRetryWait : wait;
}

String _rateLimitMessage(AppLocalizations l10n, Object error) {
  final wait = retryWaitFor(error);
  if (wait == null) return l10n.matrixAuthRateLimited;
  final seconds = (wait.inMilliseconds / 1000).ceil();
  return seconds < 60
      ? l10n.matrixAuthRateLimitedSeconds(seconds)
      : l10n.matrixAuthRateLimitedMinutes((seconds / 60).ceil());
}

String? _serverFailureMessage(AppLocalizations l10n, Object error) {
  if (isConnectionError(error)) return l10n.matrixAuthCannotConnect;
  if (isServerError(error)) return l10n.matrixHomeserverUnreachable;
  if (isRateLimit(error)) return _rateLimitMessage(l10n, error);
  return null;
}

String _sentence(AppLocalizations l10n, String message) {
  final line = message.trim().split('\n').first.trim();
  if (line.isEmpty) return l10n.matrixAuthUnexpected;
  return line[0].toUpperCase() + line.substring(1);
}

String oauthSignInErrorMessage(
  AppLocalizations l10n,
  Object error, {
  required String server,
}) {
  if (error is AuthBrowserUnavailable) return l10n.authOAuthNoBrowser(server);
  return _serverFailureMessage(l10n, error) ?? l10n.authOAuthFailed(server);
}

bool isOAuthSignInCancel(Object error) => error is OAuthSignInCancelled;

bool isExpectedOAuthSignInFailure(Object error) =>
    isOAuthSignInCancel(error) ||
    error is AuthBrowserUnavailable ||
    isExpectedServerFailure(error);

enum HomeserverProblem {
  unreachable,
  insecure,
  unsupportedSignIn,
  rateLimited,
  refused,
  notAServer,
  unexpected;

  bool get reported => this == unexpected;
}

HomeserverProblem homeserverProblem(Object error) {
  if (error is CleartextRefusedException) return HomeserverProblem.insecure;
  if (isConnectionError(error) || isServerError(error)) {
    return HomeserverProblem.unreachable;
  }
  if (isRateLimit(error)) return HomeserverProblem.rateLimited;
  if (error is ServerAnswerFailed) return HomeserverProblem.notAServer;
  if (error is UnsupportedSignInException) {
    return HomeserverProblem.unsupportedSignIn;
  }
  if (error is MatrixException) return HomeserverProblem.refused;
  if (isNotMatrixAnswer(error)) return HomeserverProblem.notAServer;
  return HomeserverProblem.unexpected;
}

String homeserverErrorMessage(AppLocalizations l10n, Object error) =>
    switch (homeserverProblem(error)) {
      HomeserverProblem.unreachable => l10n.matrixHomeserverUnreachable,
      HomeserverProblem.insecure => l10n.matrixHomeserverInsecure,
      HomeserverProblem.unsupportedSignIn =>
        l10n.matrixHomeserverSignInUnsupported,
      HomeserverProblem.rateLimited => _rateLimitMessage(l10n, error),
      HomeserverProblem.refused => _sentence(
        l10n,
        (error as MatrixException).errorMessage,
      ),
      HomeserverProblem.notAServer ||
      HomeserverProblem.unexpected => l10n.matrixHomeserverNotAServer,
    };
