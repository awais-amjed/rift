import 'dart:async';

import '../../../data/classes/call_clip_audio.dart';
import 'call_clip_native.dart';

/// When the runner's ring of the call is kept and written, in the one order
/// clipping's promise depends on: the ring, then the `clipping` flag published
/// to the call, and only once that has gone round, writing (CALLS.md,
/// *Clipping a call*). Writing stops before anything else changes.
///
/// [update] is told the whole situation every time and works out the steps;
/// updates run one after another, so a slow publish cannot be overtaken by
/// the next change. [pause] is for Rift rejoining: writing stops at once, and
/// the flag is sent again before it starts.
class ClipRecorder {
  /// Clips waiting for the trim view, oldest dropped first.
  static const int maxQueued = 5;

  final CallClipNative _native;

  /// Publishes this client's attributes with `clipping` set to the value,
  /// answering whether the call has them.
  final Future<bool> Function(bool clipping) _publish;

  int _seconds = 0;
  bool _mic = false;
  String? _call;
  bool _published = false;
  bool _claim = false;
  bool? _writing;
  // Moved on by [pause]: a publish that was already on its way when the
  // connection gave out must not turn writing on for the next one.
  int _generation = 0;
  Future<void> _chain = Future.value();

  ClipRecorder(
    this._native, {
    required Future<bool> Function(bool clipping) publish,
  }) : _publish = publish;

  bool get available => _native.available;

  /// Whether the ring is taking in the call now.
  bool get recording => _writing == true;

  /// Whether the flag this client last sent says it is clipping.
  bool get flagged => _published;

  /// What this client's attributes should say whenever they are sent, for
  /// any reason: clipping only while the recorder means to be. A flag sent
  /// before a rejoin is not still claimed once clipping is off.
  bool get claiming => _claim;

  /// [call] names the call ([LiveKitState.callKey]): another one starts
  /// with an empty ring, so a clip never joins one call onto the next.
  Future<void> update({
    required bool enabled,
    required bool connected,
    required bool inCall,
    required String? call,
    required int seconds,
    required bool includeMic,
  }) {
    final run = _chain.then(
      (_) => _apply(
        enabled: enabled,
        connected: connected,
        inCall: inCall,
        call: call,
        seconds: seconds,
        includeMic: includeMic,
      ),
    );
    _chain = run.catchError((Object _) {});
    return run;
  }

  Future<void> _apply({
    required bool enabled,
    required bool connected,
    required bool inCall,
    required String? call,
    required int seconds,
    required bool includeMic,
  }) async {
    final wantSeconds = enabled && inCall && _native.available ? seconds : 0;
    final wantMic = wantSeconds > 0 && includeMic;
    final wantFlag = wantSeconds > 0 && connected;

    if (!wantFlag && _writing != false) {
      _native.setWriting(false);
      _writing = false;
    }
    if (call != _call) {
      _call = call;
      if (_seconds > 0) {
        if (_writing != false) {
          _native.setWriting(false);
          _writing = false;
        }
        _native.configure(0, includeMic: false);
        _seconds = 0;
        _mic = false;
      }
    }
    if (wantSeconds != _seconds || wantMic != _mic) {
      _native.configure(wantSeconds, includeMic: wantMic);
      _seconds = wantSeconds;
      _mic = wantMic;
    }
    if (!wantFlag) {
      final was = _published;
      _claim = false;
      _published = false;
      if (was && connected) await _publish(false);
      return;
    }
    if (!_published) {
      final generation = _generation;
      _claim = true;
      final told = await _publish(true);
      if (generation != _generation) return;
      _published = told;
      if (!told) return;
    }
    if (_writing != true) {
      _native.setWriting(true);
      _writing = true;
    }
  }

  /// The connection gave out, or is being made again: stop at once. The flag
  /// counts as unsent, since the next room may not have it.
  void pause() {
    _generation++;
    _native.setWriting(false);
    _writing = false;
    _published = false;
  }

  /// What the ring holds now, while clipping is on.
  CallClipAudio? snapshot() => _seconds > 0 ? _native.snapshot() : null;

  /// [queue] with [clip] added, keeping the newest [maxQueued].
  static List<CallClipAudio> enqueue(
    List<CallClipAudio> queue,
    CallClipAudio clip,
  ) {
    final next = [...queue, clip];
    return next.length <= maxQueued
        ? next
        : next.sublist(next.length - maxQueued);
  }
}
