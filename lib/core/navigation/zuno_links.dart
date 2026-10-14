import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:url_launcher/url_launcher.dart';

import '../errors/caught_errors.dart';
import '../l10n/l10n.dart';

final donateUri = Uri.parse('https://zuno.chat/#donate');
final privacyPolicyUri = Uri.parse('https://zuno.chat/privacy');
final termsUri = Uri.parse('https://zuno.chat/terms');
final securityUri = Uri.parse('https://zuno.chat/security');
final sourceCodeUri = Uri.parse('https://github.com/Zuno-Chat/zuno-chat');

typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> openExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

String linkNotOpenedMessage(AppLocalizations l10n, Uri uri) {
  if (uri.scheme.toLowerCase() == 'mailto') {
    return l10n.navigationEmailNotOpened(uri.path);
  }
  final target = uri.hasFragment ? '${uri.path}#${uri.fragment}' : uri.path;
  return l10n.navigationLinkNotOpened('${uri.host}$target');
}

Future<void> openLink(
  BuildContext context,
  Uri uri, {
  required UrlOpener openUrl,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  var opened = false;
  try {
    opened = await openUrl(uri);
  } catch (e, s) {
    if (!noAppOpensLink(e)) reportCaught('open a link', e, s);
  }
  if (!opened) {
    messenger.showSnackBar(
      SnackBar(content: Text(linkNotOpenedMessage(l10n, uri))),
    );
  }
}

bool noAppOpensLink(Object error) =>
    error is PlatformException && error.code == 'ACTIVITY_NOT_FOUND';
