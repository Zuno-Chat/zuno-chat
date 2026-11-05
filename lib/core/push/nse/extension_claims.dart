import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../errors/best_effort.dart';
import '../../matrix/client/matrix_client_provider.dart';
import 'nse_app_channel.dart';

const maxParkedClaims = 32;

class ExtensionClaims {
  ExtensionClaims(this._channel) {
    _channel.onAlertHidden(() {
      _hidden++;
      unawaited(_retryReleased());
    });
  }

  final NseAppChannel _channel;
  final _parked = <ExtensionClaim, Future<void> Function()>{};
  var _hidden = 0;

  Future<bool> deferredToExtension(
    ExtensionClaim claim, {
    required Future<void> Function() retry,
  }) async {
    final hiddenBefore = _hidden;
    if (!(await _channel.shownByExtension([claim])).contains(claim)) {
      return false;
    }
    _parked
      ..remove(claim)
      ..[claim] = retry;
    while (_parked.length > maxParkedClaims) {
      _parked.remove(_parked.keys.first);
    }
    if (_hidden != hiddenBefore) unawaited(_retryReleased());
    return true;
  }

  Future<void> _retryReleased() async {
    if (_parked.isEmpty) return;
    final claims = [..._parked.keys];
    final stillShown = await _channel.shownByExtension(claims);
    for (final claim in claims) {
      if (stillShown.contains(claim)) continue;
      if (_parked.remove(claim) case final retry?) {
        unawaited(
          runBestEffort(retry, label: 'post an alert the app hid in front'),
        );
      }
    }
  }

  void dispose() {
    _channel.onAlertHidden(null);
    _parked.clear();
  }
}

final extensionClaimsProvider = Provider<ExtensionClaims>((ref) {
  ref.watch(matrixClientProvider);
  final claims = ExtensionClaims(ref.watch(nseAppChannelProvider));
  ref.onDispose(claims.dispose);
  return claims;
});
