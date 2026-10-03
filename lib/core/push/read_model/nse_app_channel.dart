import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class NseUtd {
  const NseUtd({required this.room, required this.event, required this.ts});

  final String room;
  final String event;
  final int ts;
}

class NseOutcomeReport {
  const NseOutcomeReport({
    this.counters = const {},
    this.utd = const [],
    this.generation,
  });

  final Map<String, int> counters;
  final List<NseUtd> utd;
  final String? generation;

  static NseOutcomeReport fromChannel(Object? value) {
    final counters = <String, int>{};
    final utd = <NseUtd>[];
    String? generation;
    for (final record in value is List ? value : const []) {
      if (record is! Map) continue;
      switch (record['kind']) {
        case 'counter':
          final key = record['key'];
          final count = record['count'];
          if (key is String && count is int) counters[key] = count;
        case 'utd':
          final room = record['room'];
          final event = record['event'];
          final ts = record['ts'];
          if (room is String && event is String && ts is int) {
            utd.add(NseUtd(room: room, event: event, ts: ts));
          }
        case 'generation':
          generation = record['value'] as String?;
      }
    }
    return NseOutcomeReport(
      counters: counters,
      utd: utd,
      generation: generation,
    );
  }
}

class NseAppChannel {
  const NseAppChannel({this.capabilities, this.channel = nseChannel});

  final PlatformCapabilities? capabilities;
  final MethodChannel channel;

  bool get _enabled => (capabilities ?? ambientCapabilities).nseNotifications;

  Future<void> writeShown(List<String> keys) async {
    if (!_enabled || keys.isEmpty) return;
    await _invoke<Object?>('writeShown', {'e': keys});
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
    } on PlatformException catch (e) {
      debugPrint('zuno/nse: $method failed ($e)');
      return null;
    }
  }
}

final nseAppChannelProvider = Provider<NseAppChannel>(
  (ref) => NseAppChannel(capabilities: ref.watch(platformCapabilitiesProvider)),
);
