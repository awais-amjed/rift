import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../helper_methods.dart';
import 'soundboard_play.dart';

/// Plays soundboard clips out of this device's own speakers.
///
/// A pool of one-shot players, the same shape as [SoundService] and for the
/// same reason: two clips landing together must not cut each other off, so
/// each gets a player and hands it back when it is done.
///
/// Two things here are not in [SoundService], and both belong to the listener
/// rather than to whoever pressed the button:
///
///   * **volume** is resolved by the caller and passed in, per person and
///     overall, so a loud friend can be turned down without turning the room
///     down;
///   * **the cutoff** stops anything still playing after
///     [SoundboardPlay.maxPlayback], whatever the clip claims its length is.
class SoundboardPlayer {
  SoundboardPlayer._();
  static final SoundboardPlayer instance = SoundboardPlayer._();

  /// How many clips may be audible at once. Past this the oldest is stopped:
  /// six people pressing at the same moment is noise, and a pool with no
  /// ceiling is a pool somebody can exhaust.
  static const int _maxConcurrent = 4;

  final List<AudioPlayer> _playing = [];

  /// Start [source] at [volume] (0–1). Returns once playback has been asked
  /// for, not once it has finished.
  Future<void> play(Source source, {required double volume}) async {
    if (volume <= 0) return;

    while (_playing.length >= _maxConcurrent) {
      await _retire(_playing.first);
    }

    final player = AudioPlayer();
    _playing.add(player);
    try {
      await player.setVolume(volume.clamp(0.0, 1.0));
      await player.play(source);
    } catch (e) {
      HelperMethods.printDebug('SoundboardPlayer: could not play – $e');
      await _retire(player);
      return;
    }
    unawaited(_recycle(player));
  }

  /// Stop everything — leaving a call, or being deafened halfway through
  /// somebody's airhorn.
  Future<void> stopAll() async {
    for (final player in List<AudioPlayer>.from(_playing)) {
      await _retire(player);
    }
  }

  /// Wait for the clip to end, the cutoff to fire, or the wait itself to go
  /// wrong — whichever comes first — then hand the player back.
  ///
  /// The delay is raced rather than used as a `timeout`, for the reason
  /// [SoundService] documents: `onPlayerComplete` is typed `Stream<void>` and
  /// carries an `AudioEvent`, so a `timeout` on it throws inside its own
  /// callback and the disposal is never scheduled at all.
  Future<void> _recycle(AudioPlayer player) async {
    try {
      await Future.any([
        player.onPlayerComplete.first.then<void>((_) {}),
        Future<void>.delayed(SoundboardPlay.maxPlayback),
      ]);
    } catch (e) {
      HelperMethods.printDebug('SoundboardPlayer: playback wait failed – $e');
    }
    await _retire(player);
  }

  Future<void> _retire(AudioPlayer player) async {
    if (!_playing.remove(player)) return;
    try {
      await player.stop();
    } catch (_) {
      // Already finished, or never started.
    }
    try {
      await player.dispose();
    } catch (e) {
      HelperMethods.printDebug('SoundboardPlayer: could not dispose – $e');
    }
  }
}
