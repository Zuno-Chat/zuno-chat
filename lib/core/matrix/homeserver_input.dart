const homeserverShapeMessage =
    'Enter a hostname, such as chat.example.org, or a full https:// address';

typedef HomeserverInput = ({Uri? uri, String? error});

HomeserverInput parseHomeserverInput(String raw) {
  final input = raw.trim();
  if (input.isEmpty) {
    return (uri: null, error: 'Enter a server, such as chat.example.org');
  }

  if (input.startsWith('@')) {
    return (
      uri: null,
      error:
          'That looks like a username. Enter just the server part, such as '
          'chat.example.org',
    );
  }

  if (input.contains(RegExp(r'\s'))) {
    return (uri: null, error: homeserverShapeMessage);
  }

  final Uri uri;
  try {
    uri = Uri.parse(input.contains('://') ? input : 'https://$input');
  } on FormatException {
    return (uri: null, error: homeserverShapeMessage);
  }

  if (uri.scheme.toLowerCase() != 'https') {
    return (uri: null, error: 'Use https://. An http address is not secure.');
  }

  if (uri.host.isEmpty) {
    return (uri: null, error: homeserverShapeMessage);
  }

  return (uri: uri, error: null);
}

String homeserverInputText(Uri homeserver) {
  final hostOnly =
      !homeserver.hasPort &&
      (homeserver.path.isEmpty || homeserver.path == '/');
  return hostOnly ? homeserver.host : homeserver.toString();
}
