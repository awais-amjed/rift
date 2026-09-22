import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import '../helper_methods.dart';

/// Plays UI sound effects (e.g. join / leave channel tones).
///
/// The service manages its own [AudioPlayer] pool so that rapid successive
/// calls never block or cut off a previous sound.
class SoundService {
  SoundService._();
  static final SoundService _instance = SoundService._();
  static SoundService get instance => _instance;

  static const _joinAsset = 'audio/join.mp3';
  static const _leaveAsset = 'audio/leave.mp3';
  static const _streamStartedAsset = 'audio/stream_started.mp3';
  static const _streamEndedAsset = 'audio/stream_ended.mp3';
  static const _pttOnAsset = 'audio/ptt_on.mp3';
  static const _pttOffAsset = 'audio/ptt_off.mp3';
  static const _watchStartedAsset = 'audio/watch_started.mp3';
  static const _watchStoppedAsset = 'audio/watch_stopped.mp3';

  /// How long to wait for a sound to finish before reclaiming its player.
  static const _maxPlaybackWait = Duration(seconds: 10);

  // ──────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────

  Future<void> playJoin() => _play(_joinAsset);
  Future<void> playLeave() => _play(_leaveAsset);
  Future<void> playStreamStarted() => _play(_streamStartedAsset);
  Future<void> playStreamEnded() => _play(_streamEndedAsset);

  /// Push-to-talk opening and closing. The same two sine notes as join and
  /// leave, cut to 160ms so they never trail into the first word.
  Future<void> playPttOn() => _play(_pttOnAsset);
  Future<void> playPttOff() => _play(_pttOffAsset);

  /// Somebody starting or stopping watching a stream, heard by its sharer and
  /// the people already watching. Three quick notes, rising or falling, so it
  /// is not mistaken for anyone joining or a stream itself starting.
  Future<void> playWatchStarted() => _play(_watchStartedAsset);
  Future<void> playWatchStopped() => _play(_watchStoppedAsset);

  // ──────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────

  Future<void> _play(String asset) async {
    // A fresh player per sound so simultaneous calls don't interfere — which
    // means every one of them has to be handed back, see [_recycle].
    final player = AudioPlayer();
    try {
      await player.setVolume(0.15);
      await player.play(AssetSource(asset));
    } catch (e) {
      HelperMethods.printDebug('SoundService: failed to play $asset – $e');
      await _dispose(player);
      return;
    }
    unawaited(_recycle(player));
  }

  /// Disposes [player] once it finishes, or after [_maxPlaybackWait] if the
  /// completion event never arrives.
  ///
  /// `onPlayerComplete` is declared `Stream<void>` but carries `AudioEvent` at
  /// runtime, so `Future.timeout` on it fails a cast on its own `onTimeout`
  /// callback — which used to throw before the disposal was ever scheduled and
  /// leak a native audio pipeline per sound. Racing a plain delay avoids
  /// touching the future's type at all.
  Future<void> _recycle(AudioPlayer player) async {
    try {
      await Future.any([
        player.onPlayerComplete.first.then<void>((_) {}),
        Future<void>.delayed(_maxPlaybackWait),
      ]);
    } catch (e) {
      HelperMethods.printDebug('SoundService: playback wait failed – $e');
    }
    await _dispose(player);
  }

  Future<void> _dispose(AudioPlayer player) async {
    try {
      await player.dispose();
    } catch (e) {
      HelperMethods.printDebug('SoundService: failed to dispose player – $e');
    }
  }
}
