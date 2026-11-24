import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/classes/call_clip_audio.dart';
import '../../../src/rust/api/call_clip.dart';
import '../../../src/rust/api/cue.dart';
import '../../helper_methods.dart';
import 'clip_output.dart';
import 'clip_trim.dart';

/// The trim view's player: where the line over the waveform stands
/// ([head], a fraction of the clip), and playing on from there on the call's
/// output ([outputId], as WebRTC lists it).
///
/// The cue player can only start a sound and stop it, so a pause stops it and
/// keeps the point, and a seek while playing starts again from the new one,
/// cut from the clip there ([ClipTrim.playRange]). A play that runs out puts
/// the line back where it started, as an editor does, so Play again hears the
/// same part.
class ClipPreview extends ChangeNotifier {
  final CallClipAudio clip;
  final String? Function() outputId;

  /// Where the line stands, stepped while it plays (by a timer, as anything
  /// that runs for a while is: AGENTS.md), so `ClipPlayLine` repaints alone.
  final ValueNotifier<double> head = ValueNotifier(0);

  ClipPreview({required this.clip, required this.outputId});

  /// How often the line moves while it plays: thirty a second rather than
  /// the usual fifteen, since this is watched as it moves.
  static const Duration _step = Duration(milliseconds: 33);

  double _start = 0;
  double _end = 1;
  int? _cue;
  bool _starting = false;
  bool _disposed = false;

  /// Which play is current: a pause or seek moves it on, and a play still
  /// being made for an older one stops itself when it lands.
  int _run = 0;

  /// Whether a scrub is moving the line ([beginScrub]), and whether it was
  /// playing when that began.
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  Timer? _ended;
  Timer? _steps;

  bool get playing => _cue != null;
  bool get starting => _starting;

  /// The selection moved under a handle. What was playing was a preview of
  /// the old one and stops. The line goes to a start that moved, so Play
  /// hears the new beginning, and to the start too when it is left outside.
  void select(double start, double end) {
    final movedStart = start != _start;
    pause();
    _start = start;
    _end = end;
    if (movedStart || head.value < start || head.value > end) {
      head.value = start;
    }
  }

  void toggle() {
    if (playing || _starting) {
      pause();
    } else {
      unawaited(play());
    }
  }

  Future<void> play() async {
    if (playing || _starting || _disposed) return;
    final range = ClipTrim.playRange(
      head: head.value,
      start: _start,
      end: _end,
    );
    final pcm = ClipTrim.cut(
      clip.pcm,
      clip.channels,
      clip.duration * range.from,
      clip.duration * range.to,
      rate: clip.rate,
    );
    if (pcm.isEmpty) return;
    final run = ++_run;
    _starting = true;
    notifyListeners();
    try {
      final wav = await callClipWav(
        pcm: pcm,
        rate: clip.rate,
        channels: clip.channels,
      );
      if (run != _run) return;
      final frames = pcm.length ~/ clip.channels;
      final started = await ClipOutput.play(
        outputId(),
        (device) => playSound(
          deviceId: device,
          bytes: wav,
          volume: 1,
          maxMs: frames * 1000 ~/ clip.rate + 250,
        ),
      );
      if (run != _run) {
        unawaited(stopCue(id: started.id));
        return;
      }
      _cue = started.id;
      head.value = range.from;
      final length = clip.duration * (range.to - range.from);
      final clock = Stopwatch()..start();
      _steps = Timer.periodic(
        _step,
        (_) => head.value = ClipTrim.playhead(
          start: range.from,
          end: range.to,
          elapsed: clock.elapsed,
          length: length,
        ),
      );
      _ended = Timer(Duration(milliseconds: started.durationMs), () {
        _stopSound();
        head.value = range.from;
        notifyListeners();
      });
    } catch (e) {
      HelperMethods.printDebug('[Clips] preview failed: $e');
      HelperMethods.showError(error: "Couldn't play the clip.");
    } finally {
      if (run == _run) {
        _starting = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  /// Stops, keeping the line where it is.
  void pause() {
    _run++;
    final was = playing || _starting;
    _stopSound();
    _starting = false;
    if (was && !_disposed) notifyListeners();
  }

  /// Puts the line at [at]: playing on from there if it was playing, or only
  /// moving it during a scrub, which would otherwise start a sound on every
  /// step of the drag.
  void seek(double at) {
    final to = at.clamp(0.0, 1.0);
    if (_scrubbing) {
      head.value = to;
      return;
    }
    final resume = playing || _starting;
    pause();
    head.value = to;
    if (resume) unawaited(play());
  }

  /// A drag along the waveform began: silent while the line follows it.
  void beginScrub() {
    _resumeAfterScrub = playing || _starting;
    pause();
    _scrubbing = true;
  }

  void endScrub() {
    _scrubbing = false;
    if (_resumeAfterScrub) unawaited(play());
    _resumeAfterScrub = false;
  }

  void _stopSound() {
    _ended?.cancel();
    _ended = null;
    _steps?.cancel();
    _steps = null;
    final id = _cue;
    _cue = null;
    if (id != null) unawaited(stopCue(id: id));
  }

  @override
  void dispose() {
    _run++;
    _stopSound();
    _disposed = true;
    head.dispose();
    super.dispose();
  }
}
