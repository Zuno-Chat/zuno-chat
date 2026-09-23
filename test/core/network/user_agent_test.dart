import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:zuno/core/network/user_agent.dart';

const _agent = 'Zuno/1.2.0 (Android; im.zuno.chat)';

void main() {
  tearDown(() => HttpOverrides.global = null);

  test('names the app, its version and its package', () {
    expect(zunoUserAgent('1.2.0'), _agent);
  });

  test('every HTTP client created after install carries it', () async {
    await installUserAgent(version: () async => '1.2.0');

    expect(HttpClient().userAgent, _agent);
  });

  test('reads the version from the installed package by default', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Zuno',
      packageName: 'im.zuno.chat',
      version: '1.2.0',
      buildNumber: '2',
      buildSignature: '',
    );

    await installUserAgent();

    expect(HttpClient().userAgent, _agent);
  });

  test('still names the app when the version cannot be read', () async {
    await installUserAgent(
      version: () async => throw MissingPluginException('no plugin'),
    );

    expect(HttpClient().userAgent, 'Zuno (Android; im.zuno.chat)');
  });

  test('is readable by code that sets the header itself', () async {
    await installUserAgent(version: () async => '1.2.0');

    expect(appUserAgent, _agent);
  });

  test('is unknown before install', () {
    expect(appUserAgent, isNull);
  });
}
