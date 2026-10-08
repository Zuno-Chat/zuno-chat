import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _tick = Duration(seconds: 30);

final liveLocationClockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(_tick, (_) => clock.now()),
);

DateTime watchLiveNow(WidgetRef ref) {
  ref.watch(liveLocationClockProvider);
  return clock.now();
}

String Function(DateTime time) liveClockFormat(BuildContext context) =>
    (time) => TimeOfDay.fromDateTime(time.toLocal()).format(context);
