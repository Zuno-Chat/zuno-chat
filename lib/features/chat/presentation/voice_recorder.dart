import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:record/record.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/files/file_system.dart';
import '../../../core/files/picked_file.dart';
import '../../../core/matrix/media/media_audio_session.dart';
import '../../../core/matrix/media/voice/voice_recording.dart';
import '../../../core/ui/screen_awake.dart';
import '../../../core/ui/visible_in_front.dart';
import 'message_contents/voice_message.dart';

enum VoiceRecordingProblem { microphoneDenied, didNotStart, notSent }

enum _Phase { idle, starting, recording, stopping }

enum _Press { none, held, handsFree }

enum _Ending { send, keep, discard }

const _holdThreshold = Duration(milliseconds: 150);
const _minHoldToSend = Duration(milliseconds: 300);
const _shortestSent = Duration(milliseconds: 100);
const _longest = Duration(minutes: 5);
const _slideToCancelThreshold = 80.0;

class VoiceRecorder extends ChangeNotifier {
  VoiceRecorder({
    required this._setup,
    required this._audio,
    required this._onRecorded,
    required this._onProblem,
    required this._keep,
    required this._kept,
    this._createRecorder = AudioRecorder.new,
  }) {
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (!isInFront(state)) unawaited(_interrupted());
      },
    );
  }

  final VoiceRecordingSetup _setup;
  final MediaAudioSession _audio;
  final Future<void> Function(VoiceClip clip) _onRecorded;
  final void Function(VoiceRecordingProblem problem) _onProblem;
  final void Function(VoiceClip? clip) _keep;
  final VoiceClip? Function() _kept;
  final AudioRecorder Function() _createRecorder;

  late final AppLifecycleListener _lifecycle;
  AudioRecorder? _recorder;
  StreamSubscription<RecordState>? _recorderState;
  Future<void>? _starting;
  final _elapsed = ValueNotifier(Duration.zero);
  _Phase _phase = _Phase.idle;
  _Press _press = _Press.none;
  _Ending? _endOnceStarted;
  bool _willCancel = false;
  String? _path;
  DateTime? _startedAt;
  final List<double> _waveform = [];
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _ticker;
  Timer? _limit;
  Timer? _holdTimer;
  Offset? _downPosition;
  bool _disposed = false;

  bool get isRecording =>
      _phase == _Phase.recording || _phase == _Phase.stopping;

  bool get handsFree => _press == _Press.handsFree;

  bool get willCancel => _willCancel;

  VoiceClip? get kept => _kept();

  ValueListenable<Duration> get elapsed => _elapsed;

  Duration get _sinceStart {
    final startedAt = _startedAt;
    return startedAt == null
        ? Duration.zero
        : clock.now().difference(startedAt);
  }

  void pointerDown(PointerDownEvent event) {
    if (_press == _Press.handsFree) return;
    _downPosition = event.position;
    _press = _Press.none;
    _holdTimer = Timer(_holdThreshold, () {
      _holdTimer = null;
      _press = _Press.held;
      unawaited(_begin());
    });
  }

  void pointerMove(PointerMoveEvent event) {
    if (_press != _Press.held) return;
    final down = _downPosition;
    if (down == null || _disposed) return;
    final willCancel = (event.position - down).dy < -_slideToCancelThreshold;
    if (willCancel == _willCancel) return;
    _willCancel = willCancel;
    notifyListeners();
  }

  Future<void> pointerUp(PointerUpEvent event) async {
    _downPosition = null;
    if (_press == _Press.handsFree) {
      _press = _Press.none;
      await _finish(_Ending.send);
      return;
    }
    final holdTimer = _holdTimer;
    if (holdTimer != null) {
      holdTimer.cancel();
      _holdTimer = null;
      _press = _Press.handsFree;
      await _begin();
      return;
    }
    if (_press == _Press.held) {
      _press = _Press.none;
      await _released();
    }
  }

  Future<void> pointerCancel(PointerCancelEvent event) async {
    _press = _Press.none;
    await _interrupted();
  }

  Future<void> cancel() => _finish(_Ending.discard);

  Future<void> sendKept() async {
    final clip = kept;
    deleteKept();
    if (clip != null) await _onRecorded(clip);
  }

  void deleteKept() {
    if (kept == null) return;
    _keep(null);
    notifyListeners();
  }

  Future<void> _interrupted() async {
    _downPosition = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    await _finish(_Ending.keep);
  }

  Future<AudioRecorder> _readyRecorder() async {
    final existing = _recorder;
    if (existing != null) return existing;
    final recorder = _recorder = _createRecorder();
    _recorderState = recorder.onStateChanged().listen(
      (state) {
        if (state != RecordState.record) unawaited(_finish(_Ending.keep));
      },
      onError: (Object e, StackTrace s) {
        reportCaught('voice recorder', e, s);
        unawaited(_finish(_Ending.keep));
      },
    );
    await recorder.ios?.manageAudioSession(!_audio.ownsRecordingSession);
    return recorder;
  }

  Future<void> _begin() async {
    if (_phase != _Phase.idle) return;
    if (!isInFront(WidgetsBinding.instance.lifecycleState)) {
      _press = _Press.none;
      return;
    }
    _phase = _Phase.starting;
    final starting = _starting = _start();
    await starting;
    _starting = null;
  }

  Future<void> _start() async {
    final AudioRecorder recorder;
    final String path;
    try {
      recorder = await _readyRecorder();
      if (!await recorder.hasPermission(request: false)) {
        final allowed = await recorder.hasPermission();
        _giveUp(allowed ? null : VoiceRecordingProblem.microphoneDenied);
        return;
      }
      path = await newVoiceFilePath(_setup.extension);
      await _audio.beginRecording(this);
      await recorder.start(_setup.config, path: path);
    } catch (e, s) {
      reportCaught('start recording', e, s);
      await _audio.endRecording(this);
      _giveUp(VoiceRecordingProblem.didNotStart);
      return;
    }
    ScreenAwake.instance.claim(this);
    _waveform.clear();
    _startedAt = clock.now();
    _phase = _Phase.recording;
    _path = path;
    _willCancel = false;
    final ending = _endOnceStarted;
    if (ending != null) {
      _endOnceStarted = null;
      await _finish(ending);
      return;
    }
    _elapsed.value = Duration.zero;
    notifyListeners();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _elapsed.value += const Duration(seconds: 1),
    );
    _limit = Timer(_longest, () => unawaited(_finish(_Ending.keep)));
    _amplitudeSub = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amplitude) {
          _waveform.add(normalizedAmplitude(amplitude.current));
        });
  }

  void _giveUp(VoiceRecordingProblem? problem) {
    _phase = _Phase.idle;
    _press = _Press.none;
    _endOnceStarted = null;
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
      _press = _Press.handsFree;
      if (!_disposed) notifyListeners();
      return;
    }
    await _finish(_Ending.send);
  }

  Future<void> _stopTimers() async {
    _ticker?.cancel();
    _ticker = null;
    _limit?.cancel();
    _limit = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  void _clear() {
    _phase = _Phase.idle;
    _press = _Press.none;
    _path = null;
    _willCancel = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> _finish(_Ending ending) async {
    if (_phase == _Phase.starting) {
      _endOnceStarted ??= ending;
      return;
    }
    if (_phase != _Phase.recording) return;
    _phase = _Phase.stopping;
    final path = _path;
    final duration = _sinceStart;
    _startedAt = null;
    await _stopTimers();
    final waveform = resampleWaveform(_waveform);
    final stopped = await _stopRecorder();
    await _audio.endRecording(this);
    ScreenAwake.instance.release(this);
    if (ending != _Ending.keep) _clear();

    final recorded = ending == _Ending.discard
        ? null
        : await _readRecording(stopped);
    await Future.wait({?path, ?stopped}.map(discardTemporaryCopy));
    final clip = recorded == null || duration < _shortestSent
        ? null
        : await _clipOf(recorded, duration, waveform);

    if (ending == _Ending.keep) {
      if (clip != null) _keep(clip);
      _clear();
    } else if (clip != null && !_disposed) {
      await _onRecorded(clip);
    }
  }

  Future<String?> _stopRecorder() async {
    try {
      return await _recorder?.stop();
    } catch (e, s) {
      reportCaught('stop recording', e, s);
      return null;
    }
  }

  Future<Uint8List?> _readRecording(String? path) async {
    if (path == null) return null;
    try {
      return await fileSystem.file(path).readAsBytes();
    } catch (e, s) {
      reportCaught('read recording', e, s);
      return null;
    }
  }

  Future<VoiceClip?> _clipOf(
    Uint8List recorded,
    Duration duration,
    List<int> waveform,
  ) async {
    final bytes = await _setup.toOggOpus(recorded);
    if (bytes == null) {
      if (!_disposed) _onProblem(VoiceRecordingProblem.notSent);
      return null;
    }
    return (bytes: bytes, duration: duration, waveform: waveform);
  }

  Future<void> _close() async {
    await _finish(_Ending.keep);
    await _starting;
    await _recorderState?.cancel();
    await runBestEffort(_recorder?.dispose, label: 'release the recorder');
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    _holdTimer?.cancel();
    unawaited(_stopTimers());
    unawaited(_close());
    _elapsed.dispose();
    super.dispose();
  }
}
