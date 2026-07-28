import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

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

  // ──────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────

  Future<void> playJoin() => _play(_joinAsset);
  Future<void> playLeave() => _play(_leaveAsset);
  Future<void> playStreamStarted() => _play(_streamStartedAsset);
  Future<void> playStreamEnded() => _play(_streamEndedAsset);

  // ──────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────

  Future<void> _play(String asset) async {
    try {
      // A fresh player per sound so simultaneous calls don't interfere.
      final player = AudioPlayer();
      await player.setVolume(0.15);
      await player.play(AssetSource(asset));
      // Dispose once playback finishes (or after a generous timeout).
      player.onPlayerComplete.first
          .timeout(const Duration(seconds: 10), onTimeout: () {})
          .then((_) => player.dispose())
          .catchError((_) => player.dispose());
    } catch (e) {
      debugPrint('SoundService: failed to play $asset – $e');
    }
  }
}
