import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/files/file_system.dart';
import '../../../core/files/unique_name.dart';
import '../../../core/matrix/voice_audio_session.dart';
import '../../../core/matrix/voice_recording.dart';
import 'message_contents/voice_message.dart';

enum VoiceRecordingProblem { microphoneDenied, didNotStart, notSent }

typedef VoiceClip = ({Uint8List bytes, Duration duration, List<int> waveform});

const _holdThreshold = Duration(milliseconds: 150);
const _minHoldToSend = Duration(milliseconds: 300);
const _shortestSent = Duration(milliseconds: 100);
const _slideToCancelThreshold = 80.0;

class VoiceRecorder extends ChangeNotifier {
  VoiceRecorder({
    required this._setup,
    required this._audio,
    required this._onRecorded,
    required this._onProblem,
    this._createRecorder = AudioRecorder.new,
  });

  final VoiceRecordingSetup _setup;
  final VoiceAudioSession _audio;
  final Future<void> Function(VoiceClip clip) _onRecorded;
  final void Function(VoiceRecordingProblem problem) _onProblem;
  final AudioRecorder Function() _createRecorder;

  AudioRecorder? _recorder;
  final _elapsed = ValueNotifier(Duration.zero);
  bool _recording = false;
  bool _handsFree = false;
  bool _willCancel = false;
  String? _path;
  DateTime? _startedAt;
  final List<double> _waveform = [];
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _ticker;
  Timer? _holdTimer;
  Offset? _downPosition;
  bool _held = false;
  bool _disposed = false;

  bool get isRecording => _recording;

  bool get handsFree => _handsFree;

  bool get willCancel => _willCancel;

  ValueListenable<Duration> get elapsed => _elapsed;

  Duration get _sinceStart {
    final startedAt = _startedAt;
    return startedAt == null
        ? Duration.zero
        : clock.now().difference(startedAt);
  }

  void pointerDown(PointerDownEvent event) {
    if (_handsFree) return;
    _downPosition = event.position;
    _held = false;
    _holdTimer = Timer(_holdThreshold, () {
      _holdTimer = null;
      _held = true;
      unawaited(_start());
    });
  }

  void pointerMove(PointerMoveEvent event) {
    if (!_held) return;
    final down = _downPosition;
    if (down == null || _disposed) return;
    final willCancel = (event.position - down).dy < -_slideToCancelThreshold;
    if (willCancel == _willCancel) return;
    _willCancel = willCancel;
    notifyListeners();
  }

  Future<void> pointerUp(PointerUpEvent event) async {
    _downPosition = null;
    if (_handsFree) {
      _handsFree = false;
      await _stopAndSend();
      return;
    }
    final holdTimer = _holdTimer;
    if (holdTimer != null) {
      holdTimer.cancel();
      _holdTimer = null;
      _handsFree = true;
      await _start();
      return;
    }
    if (_held) {
      _held = false;
      await _released();
    }
  }

  Future<void> pointerCancel(PointerCancelEvent event) async {
    _downPosition = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    final wasRecording = _held || _handsFree;
    _held = false;
    _handsFree = false;
    if (wasRecording) await cancel();
  }

  Future<void> cancel() async {
    await _stopRecorder();
    final path = _path;
    if (path != null) {
      final file = fileSystem.file(path);
      if (await file.exists()) await file.delete();
    }
    _startedAt = null;
    _clear();
  }

  Future<AudioRecorder> _readyRecorder() async {
    final existing = _recorder;
    if (existing != null) return existing;
    final recorder = _recorder = _createRecorder();
    await recorder.ios?.manageAudioSession(!_audio.ownsRecordingSession);
    return recorder;
  }

  Future<void> _start() async {
    try {
      final recorder = await _readyRecorder();
      if (!await recorder.hasPermission(request: false)) {
        final allowed = await recorder.hasPermission();
        _giveUp(allowed ? null : VoiceRecordingProblem.microphoneDenied);
        return;
      }
      final dir = await temporaryDirectory();
      final path = p.join(
        dir.path,
        'voice-${uniqueName()}.${_setup.extension}',
      );
      await _audio.beginRecording(this);
      await recorder.start(_setup.config, path: path);
      if (_disposed) return;
      _waveform.clear();
      _startedAt = clock.now();
      _recording = true;
      _path = path;
      _elapsed.value = Duration.zero;
      _willCancel = false;
      notifyListeners();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed) _elapsed.value += const Duration(seconds: 1);
      });
      _amplitudeSub = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            _waveform.add(normalizedAmplitude(amplitude.current));
          });
    } catch (e, s) {
      reportCaught('start recording', e, s);
      await _audio.endRecording(this);
      _giveUp(VoiceRecordingProblem.didNotStart);
    }
  }

  void _giveUp(VoiceRecordingProblem? problem) {
    _handsFree = false;
    _held = false;
    if (_disposed) return;
    notifyListeners();
    if (problem != null) _onProblem(problem);
  }

  Future<void> _released() async {
    if (_willCancel) {
      await cancel();
      return;
    }
    if (_sinceStart < _minHoldToSend) {
      _handsFree = true;
      if (!_disposed) notifyListeners();
      return;
    }
    await _stopAndSend();
  }

  Future<void> _stopSampling() async {
    _ticker?.cancel();
    _ticker = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  void _clear() {
    if (_disposed) return;
    _recording = false;
    _path = null;
    _willCancel = false;
    _handsFree = false;
    notifyListeners();
  }

  Future<String?> _stopRecorder() async {
    await _stopSampling();
    final path = await _recorder?.stop();
    await _audio.endRecording(this);
    return path;
  }

  Future<void> _stopAndSend() async {
    final path = await _stopRecorder();
    final duration = _sinceStart;
    final waveform = resampleWaveform(_waveform);
    _startedAt = null;
    _clear();
    if (path == null) return;

    final file = fileSystem.file(path);
    final recorded = await file.readAsBytes();
    await file.delete();
    if (duration < _shortestSent || _disposed) return;

    final bytes = _setup.toOggOpus(recorded);
    if (bytes == null) {
      _onProblem(VoiceRecordingProblem.notSent);
      return;
    }
    await _onRecorded((bytes: bytes, duration: duration, waveform: waveform));
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _amplitudeSub?.cancel();
    _holdTimer?.cancel();
    _recorder?.dispose();
    unawaited(_audio.endRecording(this));
    _elapsed.dispose();
    super.dispose();
  }
}
