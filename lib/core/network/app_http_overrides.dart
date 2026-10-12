import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../errors/caught_errors.dart';
import '../platform/app_platform.dart';

String zunoUserAgent(String? version, {AppPlatform? platform}) {
  final product = version == null ? 'Zuno' : 'Zuno/$version';
  final system = switch (platform ?? currentAppPlatform) {
    AppPlatform.android => 'Android',
    AppPlatform.ios => 'iOS',
  };
  return '$product ($system; im.zuno.chat)';
}

class CleartextRefusedException implements Exception {
  const CleartextRefusedException(this.uri);

  final Uri uri;

  @override
  String toString() =>
      'CleartextRefusedException: refused ${uri.scheme}://${uri.host}';
}

class _AppHttpOverrides extends HttpOverrides {
  final String userAgent;

  _AppHttpOverrides(this.userAgent);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..userAgent = userAgent
        ..connectionFactory = (uri, proxyHost, proxyPort) =>
            _connectEncrypted(uri, proxyHost, proxyPort, context);
}

Future<ConnectionTask<Socket>> _connectEncrypted(
  Uri uri,
  String? proxyHost,
  int? proxyPort,
  SecurityContext? context,
) {
  if (!uri.isScheme('https')) {
    return Future.error(CleartextRefusedException(uri));
  }
  if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort!);
  return SecureSocket.startConnect(uri.host, uri.port, context: context);
}

String? get appUserAgent => switch (HttpOverrides.current) {
  _AppHttpOverrides(:final userAgent) => userAgent,
  _ => null,
};

Future<void> installAppHttpOverrides({
  Future<String> Function()? version,
  AppPlatform? platform,
}) async {
  String? known;
  try {
    known = await (version ?? _installedVersion)();
  } catch (e, s) {
    reportCaught('read the installed app version', e, s);
  }
  HttpOverrides.global = _AppHttpOverrides(
    zunoUserAgent(known, platform: platform),
  );
}

Future<String> _installedVersion() async =>
    (await PackageInfo.fromPlatform()).version;
