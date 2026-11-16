import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../src/rust/api/cue.dart';
import '../helper_methods.dart';
import 'host_platform.dart';
import 'soundboard_play.dart';

/// Plays soundboard clips out of this device's own speakers.
///
/// A pool of one-shot players, the same shape as [SoundService] and for the
/// same reason: two clips landing together must not cut each other off, so
/// each gets a player and hands it back when it is done. The one exception is
/// the same clip again, which starts over instead: pressed twice, an airhorn
/// over its own echo is noise, where two different clips are two people
/// answering each other.
///
/// Two things here are not in [SoundService], and both belong to the listener
/// rather than to whoever pressed the button:
///
///   * **volume** is resolved by the caller and passed in, per person and
///     overall, so a loud friend can be turned down without turning the room
///     down;
///   * **the cutoff** stops anything still playing after
///     [SoundboardPlay.maxPlayback], whatever the clip claims its length is.
///
/// Clips play with the call, on its device (`AppState.callOutputId`). The
/// player cannot pick a device on the desktop, so with one chosen, Windows and
/// Linux decode the clip with the system's decoders and play it through the
/// Rust library's cue player ([playSound]), and keep the player for when that
/// fails — the same split as [SoundService]'s cues.
class SoundboardPlayer {
  SoundboardPlayer._();
  static final SoundboardPlayer instance = SoundboardPlayer._();

  /// How many clips may be audible at once. Past this the oldest is stopped:
  /// six people pressing at the same moment is noise, and a pool with no
  /// ceiling is a pool somebody can exhaust.
  static const int _maxConcurrent = 4;

  final List<_Clip> _playing = [];

  /// Start [source], the sound [clipId], at [volume] (0–1), on [output] — a
  /// device as WebRTC lists it, or null for the system default. Whatever is
  /// still playing that same sound is stopped first. Returns once playback
  /// has been asked for, not once it has finished.
  Future<void> play(
    Source source, {
    required String clipId,
    required double volume,
    String? output,
  }) async {
    if (volume <= 0) return;

    for (final clip in List<_Clip>.from(_playing)) {
      if (clip.id == clipId) await _retire(clip);
    }
    while (_playing.length >= _maxConcurrent) {
      await _retire(_playing.first);
    }

    final level = volume.clamp(0.0, 1.0);
    final onOutput = await _playOnOutput(source, level, output);
    if (onOutput != null) {
      final clip = _Clip(clipId, cue: onOutput.id);
      _playing.add(clip);
      final lasts = math.min(
        onOutput.durationMs,
        SoundboardPlay.maxPlayback.inMilliseconds,
      );
      unawaited(
        Future<void>.delayed(
          Duration(milliseconds: lasts),
        ).then((_) => _retire(clip)),
      );
      return;
    }

    final player = AudioPlayer();
    final clip = _Clip(clipId, player: player);
    _playing.add(clip);
    try {
      await player.setVolume(level);
      await player.play(source);
    } catch (e) {
      HelperMethods.printDebug('SoundboardPlayer: could not play – $e');
      await _retire(clip);
      return;
    }
    unawaited(_recycle(clip, player));
  }

  /// Stop everything — leaving a call, or being deafened halfway through
  /// somebody's airhorn.
  Future<void> stopAll() async {
    for (final clip in List<_Clip>.from(_playing)) {
      await _retire(clip);
    }
  }

  /// [source] played through the Rust library on [output], or null where
  /// that is not done — no device named, or not Windows or Linux — or it
  /// failed, and the player should play it on the system's default instead.
  /// A clip on the wrong device is better than none.
  Future<CueStarted?> _playOnOutput(
    Source source,
    double volume,
    String? output,
  ) async {
    if (!HostPlatform.playsCuesOnChosenOutput) return null;
    // WebRTC's own "default: …" entry is the system default, which the
    // player already follows.
    if (output == null || output.isEmpty || output.startsWith('default: ')) {
      return null;
    }
    try {
      final bytes = await _bytesOf(source);
      if (bytes == null) return null;
      return await playSound(
        deviceId: output,
        bytes: bytes,
        volume: volume,
        maxMs: SoundboardPlay.maxPlayback.inMilliseconds,
      );
    } catch (e) {
      HelperMethods.printDebug('SoundboardPlayer: on $output failed – $e');
      return null;
    }
  }

  static Future<Uint8List?> _bytesOf(Source source) async => switch (source) {
    BytesSource(:final bytes) => bytes,
    DeviceFileSource(:final path) => File(path).readAsBytes(),
    _ => null,
  };

  /// Wait for the clip to end, the cutoff to fire, or the wait itself to go
  /// wrong — whichever comes first — then hand the player back.
  ///
  /// The delay is raced rather than used as a `timeout`, for the reason
  /// [SoundService] documents: `onPlayerComplete` is typed `Stream<void>` and
  /// carries an `AudioEvent`, so a `timeout` on it throws inside its own
  /// callback and the disposal is never scheduled at all.
  Future<void> _recycle(_Clip clip, AudioPlayer player) async {
    try {
      await Future.any([
        player.onPlayerComplete.first.then<void>((_) {}),
        Future<void>.delayed(SoundboardPlay.maxPlayback),
      ]);
    } catch (e) {
      HelperMethods.printDebug('SoundboardPlayer: playback wait failed – $e');
    }
    await _retire(clip);
  }

  Future<void> _retire(_Clip clip) async {
    if (!_playing.remove(clip)) return;
    final cue = clip.cue;
    if (cue != null) {
      try {
        await stopCue(id: cue);
      } catch (_) {
        // Already finished.
      }
    }
    final player = clip.player;
    if (player == null) return;
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

/// One clip that is audible: the sound [id], on the player, or as a cue in
/// the Rust library.
class _Clip {
  final String id;
  final AudioPlayer? player;
  final int? cue;

  _Clip(this.id, {this.player, this.cue});
}
