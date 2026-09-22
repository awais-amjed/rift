import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../../data/classes/participant_setting.dart';
import '../../data/enums/call_sound.dart';
import '../helper_methods.dart';

/// Plays the call's cues — join and leave, push-to-talk, streams, viewers —
/// at the volume each is set to in settings.
///
/// The service manages its own [AudioPlayer] pool so that rapid successive
/// calls never block or cut off a previous sound.
class SoundService {
  SoundService._();
  static final SoundService _instance = SoundService._();
  static SoundService get instance => _instance;

  /// The player volume at 100% on a settings slider. Twice what every cue
  /// played at before the sliders existed, so the default sits mid-track
  /// with room to go both ways — see [CallSound.defaultVolume].
  static const _ceiling = 0.3;

  /// How long to wait for a sound to finish before reclaiming its player.
  static const _maxPlaybackWait = Duration(seconds: 10);

  /// The shortest gap between two restarts of a preview. A slider reports
  /// every pixel of a drag, and restarting a tone on each would be a buzz
  /// in which no single tone, and so no volume, can be heard.
  static const _previewGap = Duration(milliseconds: 250);

  // ──────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────

  /// Plays one side of [sound] — the opening tone, or with [ending] the
  /// closing one — as [settings] says: not at all when that pair is muted,
  /// and otherwise at its share of [_ceiling].
  ///
  /// [settings] is `AppState.callSounds`, handed in rather than read here
  /// so this stays a player and the choice stays in the cubit that holds it.
  Future<void> play(
    CallSound sound,
    Map<String, ParticipantSetting> settings, {
    bool ending = false,
  }) async {
    final setting = sound.settingIn(settings);
    if (setting.muted || setting.volume <= 0) return;
    await _play(
      ending ? sound.endAsset : sound.startAsset,
      setting.volume * _ceiling,
    );
  }

  /// Plays [sound] at [volume] for somebody choosing it in settings.
  ///
  /// One player, kept, rather than one per call as [play] does: while a tone
  /// is still sounding, a drag only turns it up or down, so the change is
  /// heard *on* the sound rather than as a new one — and a long tone is not
  /// stacked on itself a dozen times by one sweep of the thumb.
  Future<void> preview(CallSound sound, double volume) async {
    final player = _previewPlayer ??= AudioPlayer();
    final gain = volume.clamp(0.0, 1.0) * _ceiling;
    try {
      if (_previewing == sound && player.state == PlayerState.playing) {
        await player.setVolume(gain);
        return;
      }
      final now = DateTime.now();
      if (now.difference(_lastPreviewStart) < _previewGap) return;
      _lastPreviewStart = now;
      _previewing = sound;
      await player.stop();
      await player.setVolume(gain);
      await player.play(AssetSource(sound.startAsset));
    } catch (e) {
      HelperMethods.printDebug('SoundService: preview failed – $e');
    }
  }

  AudioPlayer? _previewPlayer;
  CallSound? _previewing;
  DateTime _lastPreviewStart = DateTime.fromMillisecondsSinceEpoch(0);

  // ──────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────

  Future<void> _play(String asset, double volume) async {
    // A fresh player per sound so simultaneous calls don't interfere — which
    // means every one of them has to be handed back, see [_recycle].
    final player = AudioPlayer();
    try {
      await player.setVolume(volume);
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
