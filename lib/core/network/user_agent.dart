import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

String zunoUserAgent(String? version) {
  final product = version == null ? 'Zuno' : 'Zuno/$version';
  return '$product (Android; im.zuno.chat)';
}

class _UserAgentOverrides extends HttpOverrides {
  final String userAgent;

  _UserAgentOverrides(this.userAgent);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..userAgent = userAgent;
}

String? get appUserAgent => switch (HttpOverrides.current) {
  _UserAgentOverrides(:final userAgent) => userAgent,
  _ => null,
};

Future<void> installUserAgent({Future<String> Function()? version}) async {
  String? known;
  try {
    known = await (version ?? _installedVersion)();
  } catch (_) {}
  HttpOverrides.global = _UserAgentOverrides(zunoUserAgent(known));
}

Future<String> _installedVersion() async =>
    (await PackageInfo.fromPlatform()).version;
