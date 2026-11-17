import 'dart:convert';

import 'package:http/http.dart' as http;

import '../navigation/zuno_links.dart';
import '../platform/os_version.dart';
import 'app_version.dart';

typedef AvailableUpdate = ({int build, Uri link});

final _websiteManifest = Uri.parse('https://get.zuno.chat/android/latest.json');

AvailableUpdate? checkPlay(int? build, {required String packageName}) =>
    build == null
    ? null
    : (
        build: build,
        link: Uri.https('play.google.com', '/store/apps/details', {
          'id': packageName,
        }),
      );

Future<AvailableUpdate?> checkAppStore(
  http.Client client, {
  required String bundleId,
  required String osVersion,
}) async {
  final answer = await _getJson(
    client,
    Uri.https('itunes.apple.com', '/lookup', {'bundleId': bundleId}),
  );
  if (answer case {
    'results': [
      {
        'version': final String version,
        'minimumOsVersion': final String minimum,
        'trackViewUrl': final String listing,
      },
      ...,
    ],
  }) {
    final build = buildNumberOf(version);
    final link = Uri.tryParse(listing);
    if (build == null || link == null || !osAtLeast(osVersion, minimum)) {
      return null;
    }
    return (build: build, link: link);
  }
  return null;
}

Future<AvailableUpdate?> checkWebsite(http.Client client) async {
  if (await _getJson(client, _websiteManifest) case {
    'version': final String version,
  }) {
    final build = buildNumberOf(version);
    return build == null ? null : (build: build, link: downloadUri);
  }
  return null;
}

Future<Object?> _getJson(http.Client client, Uri url) async {
  final response = await client.get(url);
  if (response.statusCode != 200) return null;
  try {
    return jsonDecode(utf8.decode(response.bodyBytes));
  } on FormatException {
    return null;
  }
}
