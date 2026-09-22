import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../security/password_strength.dart';
import 'homeserver.dart';
import 'matrix_client_provider.dart';
import 'username_field.dart';

const registrationTokenStage = 'm.login.registration_token';

const supportedRegistrationStages = {
  AuthenticationTypes.dummy,
  registrationTokenStage,
};

enum RegistrationAvailability { available, unsupportedFlow, disabled, unknown }

class RegistrationSupport {
  final RegistrationAvailability availability;
  final bool requiresRegistrationToken;

  const RegistrationSupport(
    this.availability, {
    this.requiresRegistrationToken = false,
  });

  bool get isAvailable => availability == RegistrationAvailability.available;
}

bool isUiaSessionMismatch(MatrixException exception) {
  if (exception.error != MatrixError.M_FORBIDDEN) return false;
  return exception.errorMessage.toLowerCase().contains(
    'changed during the ui authentication session',
  );
}

RegistrationSupport registrationSupportFrom(
  int statusCode,
  Map<String, Object?> body,
) {
  if (statusCode == 200) {
    return const RegistrationSupport(RegistrationAvailability.available);
  }
  if (statusCode == 403) {
    return const RegistrationSupport(RegistrationAvailability.disabled);
  }
  if (statusCode != 401) {
    return const RegistrationSupport(RegistrationAvailability.unknown);
  }

  final flows = body['flows'];
  if (flows is! List) {
    return const RegistrationSupport(RegistrationAvailability.unknown);
  }
  final completable = flows
      .whereType<Map>()
      .map((flow) => flow['stages'])
      .whereType<List>()
      .where(
        (stages) => stages.every(
          (stage) =>
              stage is String && supportedRegistrationStages.contains(stage),
        ),
      )
      .map((stages) => stages.cast<String>().toList())
      .toList();
  if (completable.isEmpty) {
    return const RegistrationSupport(RegistrationAvailability.unsupportedFlow);
  }
  return RegistrationSupport(
    RegistrationAvailability.available,
    requiresRegistrationToken: completable.every(
      (stages) => stages.contains(registrationTokenStage),
    ),
  );
}

const registrationProbeTimeout = Duration(seconds: 35);

Future<RegistrationSupport> fetchRegistrationSupport(Client client) async {
  final homeserver = client.homeserver;
  if (homeserver == null) {
    return const RegistrationSupport(RegistrationAvailability.unknown);
  }
  try {
    final response = await client.httpClient
        .post(
          homeserver.resolve('_matrix/client/v3/register'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(const <String, Object?>{}),
        )
        .timeout(registrationProbeTimeout);
    final decoded = response.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(response.body);
    return registrationSupportFrom(
      response.statusCode,
      decoded is Map<String, Object?> ? decoded : const {},
    );
  } on Exception {
    return const RegistrationSupport(RegistrationAvailability.unknown);
  }
}

const maxRegistrationPasswordLength = 512;

const maxUserIdLength = 255;

String? registrationInputError({
  required String username,
  required String password,
  required String confirmPassword,
  String? serverName,
}) {
  if (username.isEmpty) return 'Choose a username';
  if (username.startsWith('@') || username.contains(':')) {
    return 'Enter just a username, without @ or a server name';
  }
  if (!RegExp('^[$signupUsernameChars]+\$').hasMatch(username)) {
    return 'Usernames can use a–z, 0–9, dots and underscores';
  }
  if (username.startsWith('_')) {
    return 'Usernames cannot start with an underscore';
  }
  if (!username.contains(RegExp('[a-z]'))) {
    return 'Usernames need at least one letter';
  }
  if ('@$username:${serverName ?? ''}'.length > maxUserIdLength) {
    return 'That username is too long';
  }
  if (password.length > maxRegistrationPasswordLength) {
    return 'Use at most $maxRegistrationPasswordLength characters';
  }
  final assessment = assessPassword(password, username: username);
  if (assessment.blocker != null) return assessment.blocker;
  if (password != confirmPassword) return 'Passwords do not match';
  return null;
}

class RegistrationProbeInconclusive implements Exception {
  const RegistrationProbeInconclusive();
}

final registrationSupportProvider =
    FutureProvider.autoDispose<RegistrationSupport>((ref) async {
      ref.watch(homeserverProvider);
      final support = await fetchRegistrationSupport(
        ref.watch(matrixClientProvider),
      );
      if (support.availability == RegistrationAvailability.unknown) {
        throw const RegistrationProbeInconclusive();
      }
      return support;
    });

sealed class RegistrationStep {
  const RegistrationStep();
}

class SendRegistrationAuth extends RegistrationStep {
  final AuthenticationData auth;

  const SendRegistrationAuth(this.auth);
}

class RegistrationCodeRefused extends RegistrationStep {
  const RegistrationCodeRefused();
}

class RegistrationStalled extends RegistrationStep {
  const RegistrationStalled();
}

class RegistrationCodeRefusedException implements Exception {
  const RegistrationCodeRefusedException();
}

AuthenticationData registrationAuthFor(
  String stage,
  String? session,
  String? code,
) {
  if (stage != registrationTokenStage) {
    return AuthenticationData(type: stage, session: session);
  }
  return AuthenticationData(
    type: stage,
    session: session,
    additionalFields: {'token': code},
  );
}

AuthenticationData initialRegistrationAuth(String? code, {String? session}) =>
    registrationAuthFor(
      code == null ? AuthenticationTypes.dummy : registrationTokenStage,
      session,
      code,
    );

RegistrationStep nextRegistrationStep({
  required MatrixException refusal,
  required String? code,
  required String? lastStageSent,
  required String? lastSessionSent,
}) {
  final completed = refusal.completedAuthenticationFlows;
  if (lastStageSent != null && !completed.contains(lastStageSent)) {
    if (lastSessionSent == null && refusal.session != null) {
      return SendRegistrationAuth(
        registrationAuthFor(lastStageSent, refusal.session, code),
      );
    }
    return lastStageSent == registrationTokenStage
        ? const RegistrationCodeRefused()
        : const RegistrationStalled();
  }

  final usable = (refusal.authenticationFlows ?? const <AuthenticationFlow>[])
      .map((flow) => flow.stages)
      .where(
        (stages) => stages.every(
          (stage) =>
              supportedRegistrationStages.contains(stage) &&
              (stage != registrationTokenStage || code != null),
        ),
      )
      .toList();
  if (usable.isEmpty) return const RegistrationStalled();

  final flow = usable.firstWhere(
    (stages) => !stages.contains(registrationTokenStage),
    orElse: () => usable.first,
  );
  final remaining = flow.where((stage) => !completed.contains(stage));
  if (remaining.isEmpty) return const RegistrationStalled();
  return SendRegistrationAuth(
    registrationAuthFor(remaining.first, refusal.session, code),
  );
}

const maxRegistrationAttempts = 6;

class RegistrationProgress {
  String? session;
  bool interrupted = false;
}

const _refusalsThatKeepSession = {
  MatrixError.M_LIMIT_EXCEEDED,
  MatrixError.M_USER_IN_USE,
};

Future<void> runRegistration(
  Client client, {
  required String username,
  required String password,
  required String? code,
  required String deviceDisplayName,
  RegistrationProgress? progress,
}) async {
  progress ??= RegistrationProgress();
  final resumedSession = progress.session;
  var auth = initialRegistrationAuth(code, session: resumedSession);
  var restarted = false;
  MatrixException? refusal;
  for (var attempt = 0; attempt < maxRegistrationAttempts; attempt++) {
    try {
      await client.register(
        username: username,
        password: password,
        auth: auth,
        initialDeviceDisplayName: deviceDisplayName,
        refreshToken: true,
      );
      return;
    } on MatrixException catch (e) {
      refusal = e;
      progress.session = e.session ?? progress.session;
      final sessionLost =
          resumedSession != null &&
          attempt == 0 &&
          (e.requireAdditionalAuthentication
              ? e.session != null && e.session != resumedSession
              : !_refusalsThatKeepSession.contains(e.error));
      if ((isUiaSessionMismatch(e) || sessionLost) && !restarted) {
        restarted = true;
        progress.session = null;
        auth = initialRegistrationAuth(code);
        continue;
      }
      if (e.error == MatrixError.M_USER_IN_USE && progress.interrupted) {
        try {
          await client.login(
            LoginType.mLoginPassword,
            identifier: AuthenticationUserIdentifier(user: username),
            password: password,
            initialDeviceDisplayName: deviceDisplayName,
            refreshToken: true,
          );
          return;
        } on MatrixException {
          throw e;
        }
      }
      if (!e.requireAdditionalAuthentication) rethrow;
      switch (nextRegistrationStep(
        refusal: e,
        code: code,
        lastStageSent: auth.type,
        lastSessionSent: auth.session,
      )) {
        case SendRegistrationAuth(auth: final next):
          auth = next;
        case RegistrationCodeRefused():
          throw const RegistrationCodeRefusedException();
        case RegistrationStalled():
          rethrow;
      }
    } on Exception {
      progress.interrupted = true;
      rethrow;
    }
  }
  throw refusal!;
}
