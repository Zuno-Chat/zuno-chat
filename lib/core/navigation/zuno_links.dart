import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final donateUri = Uri.parse('https://zuno.chat/#donate');
final privacyPolicyUri = Uri.parse('https://zuno.chat/privacy');
final termsUri = Uri.parse('https://zuno.chat/terms');
final sourceCodeUri = Uri.parse('https://github.com/Zuno-Chat/zuno-chat');

typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> openExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

String linkNotOpenedMessage(Uri uri) {
  final target = uri.hasFragment ? '${uri.path}#${uri.fragment}' : uri.path;
  return 'Link not opened. Visit ${uri.host}$target in a browser.';
}

Future<void> openLink(
  BuildContext context,
  Uri uri, {
  required UrlOpener openUrl,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await openUrl(uri);
  } catch (_) {}
  if (!opened) {
    messenger.showSnackBar(SnackBar(content: Text(linkNotOpenedMessage(uri))));
  }
}
