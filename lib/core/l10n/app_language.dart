import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';
import 'app_locale.dart';

typedef AppLanguageOption = ({String tag, Locale locale});

@immutable
class AppLanguage {
  final String? tag;
  final Locale? locale;
  final List<AppLanguageOption> options;
  const AppLanguage(this.tag, {this.locale, this.options = const []});

  AppLanguageOption? get chosen =>
      options.where((option) => option.tag == tag).firstOrNull ??
      options.where((option) => option.locale == locale).firstOrNull;
}

AppLanguage? parseAppLanguage(Map<Object?, Object?>? reply) {
  if (reply == null || reply['supported'] != true) return null;
  final tag = reply['tag'] as String?;
  return AppLanguage(
    tag == null || tag.isEmpty ? null : tag,
    locale: shippedLocale(reply['locale'] as String?),
    options: [
      for (final option in (reply['options'] as List?) ?? const [])
        if (option case {'tag': final String tag, 'locale': final String name})
          if (shippedLocale(name) case final locale?)
            (tag: tag, locale: locale),
    ],
  );
}

class AppLanguageController extends AsyncNotifier<AppLanguage?> {
  bool get _inApp =>
      ref.read(platformCapabilitiesProvider).appLanguage ==
      AppLanguageSetting.inApp;

  @override
  Future<AppLanguage?> build() async {
    if (!_inApp) return null;
    try {
      return parseAppLanguage(await localeChannel.invokeMapMethod('get'));
    } catch (e, s) {
      reportCaught('read app language', e, s);
      return null;
    }
  }

  Future<void> set(String? tag) async {
    if (!_inApp) return;
    await localeChannel.invokeMethod<void>('set', {'tag': tag});
    ref.invalidateSelf();
    await future;
  }
}

final appLanguageProvider =
    AsyncNotifierProvider<AppLanguageController, AppLanguage?>(
      AppLanguageController.new,
    );
