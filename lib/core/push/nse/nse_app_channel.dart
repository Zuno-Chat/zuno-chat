import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../errors/caught_errors.dart';
import '../../platform/platform_capabilities.dart';
import 'nse_channel.dart';

class NseMark {
  const NseMark({
    required this.kind,
    required this.ts,
    this.room,
    this.call,
    this.status,
  });

  final String kind;
  final int ts;
  final String? room;
  final String? call;
  final String? status;

  static NseMark? fromChannel(Object? value) {
    if (value is! Map) return null;
    final kind = value['kind'];
    final ts = value['ts'];
    if (kind is! String || ts is! int) return null;
    return NseMark(
      kind: kind,
      ts: ts,
      room: value['room'] as String?,
      call: value['call'] as String?,
      status: value['status'] as String?,
    );
  }
}

class NseOutcomeReport {
  const NseOutcomeReport({this.counters = const {}, this.generation});

  final Map<String, int> counters;
  final String? generation;

  static NseOutcomeReport fromChannel(Object? value) {
    final counters = <String, int>{};
    String? generation;
    for (final record in value is List ? value : const []) {
      if (record is! Map) continue;
      switch (record['kind']) {
        case 'counter':
          final key = record['key'];
          final count = record['count'];
          if (key is String && count is int) counters[key] = count;
        case 'generation':
          generation = record['value'] as String?;
      }
    }
    return NseOutcomeReport(counters: counters, generation: generation);
  }
}

extension type const ExtensionClaim._(({String kind, String id}) _wire) {
  const ExtensionClaim.event(String eventId)
    : this._((kind: 'event', id: eventId));

  const ExtensionClaim.invite(String roomId)
    : this._((kind: 'invite', id: roomId));

  Map<String, String> toChannel() => {'kind': _wire.kind, 'id': _wire.id};
}

Map<String, Object?> _claimsArgs(List<ExtensionClaim> claims) => {
  'claims': [for (final claim in claims) claim.toChannel()],
};

class NseAppChannel {
  const NseAppChannel({this.capabilities, this.channel = nseChannel});

  final PlatformCapabilities? capabilities;
  final MethodChannel channel;

  bool get _enabled => (capabilities ?? ambientCapabilities).nseNotifications;

  Future<void> writeShown(List<ExtensionClaim> claims) async {
    if (!_enabled || claims.isEmpty) return;
    await _invoke<Object?>('writeShown', _claimsArgs(claims));
  }

  Future<Set<ExtensionClaim>> shownByExtension(
    List<ExtensionClaim> claims,
  ) async {
    if (!_enabled || claims.isEmpty) return const {};
    final shown =
        await _invoke<List<Object?>>('shownByExtension', _claimsArgs(claims)) ??
        const [];
    return {
      for (var i = 0; i < claims.length && i < shown.length; i++)
        if (shown[i] == true) claims[i],
    };
  }

  void onAlertHidden(void Function()? hidden) {
    if (!_enabled) return;
    channel.setMethodCallHandler(
      hidden == null
          ? null
          : (call) async {
              if (call.method == 'alertHiddenInFront') hidden();
              return null;
            },
    );
  }

  Future<List<NseMark>> takeMarks() async {
    if (!_enabled) return const [];
    final value = await _invoke<List<Object?>>('takeMarks');
    return [...?value?.map(NseMark.fromChannel).nonNulls];
  }

  Future<NseOutcomeReport> readOutcomes() async {
    if (!_enabled) return const NseOutcomeReport();
    return NseOutcomeReport.fromChannel(
      await _invoke<List<Object?>>('readOutcomes'),
    );
  }

  Future<bool> setCredential(String? credential, {int? expiresTs}) async {
    if (!_enabled) return false;
    return await _invoke<bool>('setCredential', {
          'credential': credential,
          'expires_ts': expiresTs,
        }) ??
        false;
  }

  Future<int?> syncBadge(List<String> unreadTokens) async {
    if (!_enabled) return null;
    return _invoke<int>('syncBadge', {'unread': unreadTokens});
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e, s) {
      reportCaught('nse $method', e, s);
      return null;
    }
  }
}

final nseAppChannelProvider = Provider<NseAppChannel>(
  (ref) => NseAppChannel(capabilities: ref.watch(platformCapabilitiesProvider)),
);
