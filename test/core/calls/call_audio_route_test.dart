import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/call_audio_route.dart';
import 'package:zuno/core/calls/models/call_kind.dart';

void main() {
  const bluetooth = CallAudioRoute.bluetooth;
  const wired = CallAudioRoute.wiredHeadset;
  const speaker = CallAudioRoute.speaker;
  const earpiece = CallAudioRoute.earpiece;

  group('startingRoute', () {
    test('without a headset a voice call starts at the ear, a video call on '
        'the speaker', () {
      expect(startingRoute(CallKind.voice, {}), earpiece);
      expect(startingRoute(CallKind.video, {}), speaker);
    });

    test('a connected headset wins, even for a video call', () {
      expect(startingRoute(CallKind.video, {wired}), wired);
      expect(startingRoute(CallKind.voice, {wired, bluetooth}), bluetooth);
    });
  });

  group('toggledRoute', () {
    test('anything but the speaker goes to the speaker', () {
      expect(toggledRoute(earpiece, {}), speaker);
      expect(toggledRoute(bluetooth, {bluetooth}), speaker);
    });

    test('off the speaker goes back to the headset, else to the ear', () {
      expect(toggledRoute(speaker, {wired}), wired);
      expect(toggledRoute(speaker, {}), earpiece);
    });
  });

  group('routeAfterHeadsetChange', () {
    CallAudioRoute? change(
      CallAudioRoute route,
      Set<CallAudioRoute> before,
      Set<CallAudioRoute> after, {
      CallKind kind = CallKind.voice,
    }) => routeAfterHeadsetChange(
      route: route,
      before: before,
      after: after,
      kind: kind,
    );

    test('a headset connected mid-call takes the sound', () {
      expect(change(earpiece, {}, {bluetooth}), bluetooth);
      expect(change(speaker, {}, {wired}, kind: CallKind.video), wired);
    });

    test('the headset just plugged in wins over the one already in use', () {
      expect(change(bluetooth, {bluetooth}, {bluetooth, wired}), wired);
    });

    test('a change that connects nothing new leaves the route alone', () {
      expect(change(bluetooth, {bluetooth}, {bluetooth}), isNull);
      expect(change(speaker, {bluetooth}, {bluetooth}), isNull);
      expect(change(earpiece, {}, {}), isNull);
    });

    test('losing the headset in use falls back to where the call started', () {
      expect(change(bluetooth, {bluetooth}, {}), earpiece);
      expect(change(wired, {wired}, {}, kind: CallKind.video), speaker);
    });

    test('losing the headset in use moves to another one still connected', () {
      expect(change(bluetooth, {bluetooth, wired}, {wired}), wired);
    });

    test('losing a headset not in use leaves the route alone', () {
      expect(change(speaker, {bluetooth}, {}), isNull);
      expect(change(wired, {bluetooth, wired}, {wired}), isNull);
    });
  });
}
