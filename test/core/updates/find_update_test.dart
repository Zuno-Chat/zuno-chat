import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:zuno/core/updates/find_update.dart';
import 'package:zuno/core/updates/update_checks.dart';
import 'package:zuno/core/updates/update_source.dart';

import '../../helpers/fake_http.dart';

const _android = {UpdateSource.play, UpdateSource.website};
const _ios = {UpdateSource.appStore};

class _Sources {
  _Sources({this.version = '1.7.0', this.playBuild = 1007000});

  final String version;
  final int? playBuild;
  final asked = <Uri>[];
  var playChecks = 0;

  Future<AvailableUpdate?> find(String? installer, Set<UpdateSource> offered) =>
      findUpdate(
        installerStore: installer,
        installedBuild: 1006000,
        packageName: 'im.zuno.chat',
        offered: offered,
        client: FakeHttpClient((request) async {
          asked.add(request.url);
          return http.Response(
            jsonEncode(
              request.url.host == 'itunes.apple.com'
                  ? {
                      'resultCount': 1,
                      'results': [
                        {
                          'version': version,
                          'minimumOsVersion': '18.0',
                          'trackViewUrl':
                              'https://apps.apple.com/gb/app/zuno/id1',
                        },
                      ],
                    }
                  : {'version': version},
            ),
            200,
          );
        }),
        play: () async {
          playChecks++;
          return playBuild;
        },
        osVersion: 'Version 18.2 (Build 22C152)',
      );
}

void main() {
  test('a Play install asks only Play', () async {
    final sources = _Sources();
    final update = await sources.find('com.android.vending', _android);
    expect(update?.build, 1007000);
    expect(update?.link.host, 'play.google.com');
    expect(sources.playChecks, 1);
    expect(sources.asked, isEmpty);
  });

  test('an App Store install asks only Apple', () async {
    final sources = _Sources();
    final update = await sources.find('com.apple', _ios);
    expect(update?.link, Uri.parse('https://apps.apple.com/gb/app/zuno/id1'));
    expect(sources.asked.single.host, 'itunes.apple.com');
    expect(sources.playChecks, 0);
  });

  test('a website install reads only the website manifest', () async {
    final sources = _Sources();
    final update = await sources.find('com.android.chrome', _android);
    expect(update?.link, Uri.parse('https://zuno.chat/download'));
    expect(sources.asked.single.host, 'get.zuno.chat');
    expect(sources.playChecks, 0);
  });

  test('a source offering the installed build or an older one offers '
      'nothing', () async {
    for (final version in ['1.6.0', '1.5.9']) {
      expect(await _Sources(version: version).find('com.apple', _ios), isNull);
      expect(
        await _Sources(version: version).find('com.android.chrome', _android),
        isNull,
      );
    }
    for (final build in [1006000, 1005009]) {
      expect(
        await _Sources(playBuild: build).find('com.android.vending', _android),
        isNull,
      );
    }
  });
}
