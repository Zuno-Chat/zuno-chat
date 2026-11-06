import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'data/emoji_table.g.dart';
import 'drawable_probe.dart';
import 'emoji_store.dart';
import 'json.dart';

const _cacheKey = 'emoji.undrawable';
const _safeVersion = 50;
const _probeVersion = 2;

final _candidates = [
  for (final e in emojiTable) ...[
    if (e.version > _safeVersion) e.emoji,
    ...e.variants,
  ],
];

class EmojiSupport extends ChangeNotifier {
  final EmojiStore _store;
  final String _environment;
  final DrawableProbe _probe;
  final Duration _deadline;
  final void Function(Object error, StackTrace stack)? _onError;
  Set<String>? _known;
  Future<Set<String>>? _probing;

  EmojiSupport({
    required this._store,
    required this._environment,
    this._probe = probeDrawable,
    this._deadline = const Duration(seconds: 10),
    this._onError,
  });

  bool get settled => _known != null;

  Future<Set<String>> undrawable() async {
    final known = _known ??= _cached();
    if (known != null) return known;
    final probing = _probing ??= _run();
    try {
      return await probing.timeout(_deadline);
    } on TimeoutException {
      return _candidates.toSet();
    }
  }

  String get _key => '$_environment|$emojiDataVersion|$_probeVersion';

  Future<Set<String>> _run() async {
    final List<bool> drawable;
    try {
      drawable = await _probe(_candidates);
      if (drawable.length != _candidates.length) {
        throw StateError(
          'Probe answered ${drawable.length} of ${_candidates.length}',
        );
      }
    } catch (error, stack) {
      _onError?.call(error, stack);
      _probing = null;
      return _candidates.toSet();
    }
    final undrawable = {
      for (var i = 0; i < _candidates.length; i++)
        if (!drawable[i]) _candidates[i],
    };
    _known = undrawable;
    notifyListeners();
    try {
      await _store.write(
        _cacheKey,
        jsonEncode({'key': _key, 'emoji': undrawable.toList()}),
      );
    } catch (error, stack) {
      _onError?.call(error, stack);
    }
    return undrawable;
  }

  Set<String>? _cached() {
    if (decodeJsonOrNull(_store.read(_cacheKey))
        case {'key': final String stored, 'emoji': final List list}
        when stored == _key) {
      return {
        for (final e in list)
          if (e is String) e,
      };
    }
    return null;
  }
}
