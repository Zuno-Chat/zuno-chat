import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';
import 'l10n.dart';

const _channel = MethodChannel('zuno/locale');

@immutable
class AppLanguage {
  final String? tag;
  const AppLanguage(this.tag);

  Locale? get locale {
    final code = tag?.split(RegExp('[-_]')).first;
    return AppLocalizations.supportedLocales
        .where((locale) => locale.languageCode == code)
        .firstOrNull;
  }
}

AppLanguage? parseAppLanguage(Map<Object?, Object?>? reply) {
  if (reply == null || reply['supported'] != true) return null;
  final tag = reply['tag'] as String?;
  return AppLanguage(tag == null || tag.isEmpty ? null : tag);
}

class AppLanguageController extends AsyncNotifier<AppLanguage?> {
  bool get _inApp =>
      ref.read(platformCapabilitiesProvider).appLanguage ==
      AppLanguageSetting.inApp;

  @override
  Future<AppLanguage?> build() async {
    if (!_inApp) return null;
    try {
      return parseAppLanguage(await _channel.invokeMapMethod('get'));
    } catch (e, s) {
      reportCaught('read app language', e, s);
      return null;
    }
  }

  Future<void> set(String? tag) async {
    if (!_inApp) return;
    await _channel.invokeMethod<void>('set', {'tag': tag});
    ref.invalidateSelf();
    await future;
  }
}

final appLanguageProvider =
    AsyncNotifierProvider<AppLanguageController, AppLanguage?>(
      AppLanguageController.new,
    );
