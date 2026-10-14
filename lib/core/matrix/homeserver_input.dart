import '../l10n/l10n.dart';

typedef HomeserverInput = ({Uri? uri, String? error});

HomeserverInput parseHomeserverInput(AppLocalizations l10n, String raw) {
  final input = raw.trim();
  if (input.isEmpty) {
    return (uri: null, error: l10n.matrixHomeserverEnterServer);
  }

  if (input.startsWith('@')) {
    return (uri: null, error: l10n.matrixHomeserverLooksLikeUsername);
  }

  if (input.contains(RegExp(r'\s'))) {
    return (uri: null, error: l10n.matrixHomeserverShape);
  }

  final Uri uri;
  try {
    uri = Uri.parse(input.contains('://') ? input : 'https://$input');
  } on FormatException {
    return (uri: null, error: l10n.matrixHomeserverShape);
  }

  if (uri.scheme.toLowerCase() != 'https') {
    return (uri: null, error: l10n.matrixHomeserverUseHttps);
  }

  if (uri.host.isEmpty) {
    return (uri: null, error: l10n.matrixHomeserverShape);
  }

  return (uri: uri, error: null);
}

String homeserverInputText(Uri homeserver) {
  final hostOnly =
      !homeserver.hasPort &&
      (homeserver.path.isEmpty || homeserver.path == '/');
  return hostOnly ? homeserver.host : homeserver.toString();
}
