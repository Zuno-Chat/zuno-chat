import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../errors/caught_errors.dart';
import '../../matrix/currently_open_room_provider.dart';
import '../../matrix/event_display.dart';
import '../../matrix/matrix_client_provider.dart';
import '../../matrix/media_audio_session.dart';
import '../../matrix/media_gallery_group.dart';
import '../../platform/platform_capabilities.dart';
import '../../settings/app_preferences_provider.dart';
import '../settings/notification_sound_settings.dart';

const _channel = MethodChannel('zuno/conversation_tones');

enum ConversationTone { incoming, sent }

class ConversationTonePlayer {
  ConversationTonePlayer({
    required this._enabled,
    required this._recording,
    this._session,
  });

  final bool Function() _enabled;
  final bool Function() _recording;
  final MediaAudioSession? _session;
  final _lastPlayed = <ConversationTone, DateTime>{};
  final _lastGallery = <ConversationTone, String>{};

  Future<void> play(ConversationTone tone, {String? gallery}) async {
    if (!_enabled() || _recording()) return;
    if (gallery != null) {
      if (_lastGallery[tone] == gallery) return;
      _lastGallery[tone] = gallery;
    }
    final now = clock.now();
    if (!toneDue(_lastPlayed[tone], now)) return;
    _lastPlayed[tone] = now;
    Future<void> playNatively() =>
        _channel.invokeMethod<void>('play', {'tone': tone.name});
    try {
      await (_session?.duringTone(playNatively) ?? playNatively());
    } on MissingPluginException {
      return;
    } catch (e, s) {
      reportCaught('conversation tone', e, s);
    }
  }
}

bool sentToneFor(
  Event event, {
  required String? userId,
  required String? openRoomId,
}) =>
    event.senderId == userId &&
    event.status == EventStatus.sent &&
    event.room.id == openRoomId &&
    isTimelineMessage(event);

final conversationTonePlayerProvider = Provider<ConversationTonePlayer>((ref) {
  final session = ref.watch(mediaAudioSessionProvider);
  final player = ConversationTonePlayer(
    enabled: () => ref.read(conversationTonesEnabledProvider),
    recording: () => session.isRecording,
    session: ref.watch(platformCapabilitiesProvider).tonesNeedAudioSession
        ? session
        : null,
  );
  final client = ref.watch(matrixClientProvider);
  final sub = client.onTimelineEvent.stream.listen((event) {
    if (sentToneFor(
      event,
      userId: client.userID,
      openRoomId: ref.read(currentlyOpenRoomIdProvider),
    )) {
      unawaited(
        player.play(ConversationTone.sent, gallery: galleryGroupOf(event)?.id),
      );
    }
  });
  ref.onDispose(sub.cancel);
  return player;
});
