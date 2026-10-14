import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../errors/caught_errors.dart';

const localeChannel = MethodChannel('zuno/locale');

Locale? shippedLocale(String? name) => AppLocalizations.supportedLocales
    .where((locale) => locale.toString() == name)
    .firstOrNull;

Locale _flutterResolution(List<Locale> preferred) =>
    basicLocaleListResolution(preferred, AppLocalizations.supportedLocales);

final class AppLocale extends ChangeNotifier
    with WidgetsBindingObserver
    implements ValueListenable<Locale> {
  AppLocale._();

  static final instance = AppLocale._();

  Locale _value = _flutterResolution(PlatformDispatcher.instance.locales);
  bool _observing = false;

  @override
  Locale get value => _value;

  Future<void> start() async {
    final binding = WidgetsBinding.instance;
    if (!_observing) {
      binding.addObserver(this);
      _observing = true;
    }
    await _read(binding.platformDispatcher.locales);
  }

  @override
  void didChangeLocales(List<Locale>? locales) =>
      unawaited(_read(locales ?? const []));

  Future<void> _read(List<Locale> preferred) async {
    final next = await _platformChoice() ?? _flutterResolution(preferred);
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  Future<Locale?> _platformChoice() async {
    try {
      final name = await localeChannel.invokeMethod<String>('resolved');
      return shippedLocale(name) ??
          (throw StateError('the platform picked $name, which Zuno lacks'));
    } catch (e, s) {
      reportCaught('read the platform language', e, s);
      return null;
    }
  }

  @visibleForTesting
  void forgetForTest() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _observing = false;
    _value = _flutterResolution(PlatformDispatcher.instance.locales);
  }
}
