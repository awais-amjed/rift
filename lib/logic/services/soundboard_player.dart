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
/// fails — the same split as [SoundService]'s cues. A clip in Ogg goes that
/// way on Windows with no device chosen too: there the player cannot read it.
class SoundboardPlayer {
  SoundboardPlayer._();
  static final SoundboardPlayer instance = SoundboardPlayer._();

  /// How many clips may be audible at once. Past this the oldest is stopped:
  /// six people pressing at the same moment is noise, and a pool with no
  /// ceiling is a pool somebody can exhaust.
  static const int _maxConcurrent = 4;

  final List<_Clip> _playing = [];

  /// Bumped by [stopAll]. A caller reads it before the wait for a clip's
  /// bytes and hands it to [play], so a clip that finishes downloading after
  /// the call was left or the listener deafened is never started: the stop
  /// had already run, and nothing would have come back to stop it.
  int get generation => _generation;
  int _generation = 0;

  /// Start [source], the sound [clipId], at [volume] (0–1), on [output] — a
  /// device as WebRTC lists it, or null for the system default. Whatever is
  /// still playing that same sound is stopped first. Returns once playback
  /// has been asked for, not once it has finished. Nothing starts when
  /// [since], a [generation] read earlier, is no longer current.
  Future<void> play(
    Source source, {
    required String clipId,
    required double volume,
    String? output,
    int? since,
  }) async {
    if (volume <= 0) return;
    final generation = since ?? _generation;
    if (generation != _generation) return;

    // The place is taken before anything is awaited. Taken after, presses
    // landing together all passed the ceiling and the same-clip check while
    // the first was still being decoded, and a stop in that gap missed it.
    for (final clip in List<_Clip>.from(_playing)) {
      if (clip.id == clipId) unawaited(_retire(clip));
    }
    while (_playing.length >= _maxConcurrent) {
      unawaited(_retire(_playing.first));
    }
    final clip = _Clip(clipId);
    _playing.add(clip);

    final level = volume.clamp(0.0, 1.0);
    final onOutput = await _playOnOutput(source, level, output);
    if (onOutput != null) {
      // Stopped, or pushed out, while it was being decoded.
      if (!_playing.contains(clip) || generation != _generation) {
        _playing.remove(clip);
        await _stopCue(onOutput.id);
        return;
      }
      clip.cue = onOutput.id;
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
    if (!_playing.contains(clip) || generation != _generation) {
      _playing.remove(clip);
      return;
    }

    final player = AudioPlayer();
    clip.player = player;
    try {
      await player.setVolume(level);
      await player.play(source);
    } catch (e) {
      HelperMethods.printDebug('SoundboardPlayer: could not play – $e');
      await _retire(clip);
      return;
    }
    // Retired while it started: [_retire] has already let the player go.
    if (!_playing.contains(clip)) return;
    unawaited(_recycle(clip, player));
  }

  /// Stop everything — leaving a call, or being deafened halfway through
  /// somebody's airhorn — including a clip still on its way to starting.
  Future<void> stopAll() async {
    _generation++;
    for (final clip in List<_Clip>.from(_playing)) {
      await _retire(clip);
    }
  }

  static Future<void> _stopCue(int id) async {
    try {
      await stopCue(id: id);
    } catch (_) {
      // Already finished.
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
    final onDefault =
        output == null || output.isEmpty || output.startsWith('default: ');
    if (onDefault && !HostPlatform.playsOggOnlyThroughRust) return null;
    try {
      if (onDefault && !_isOgg(await _headOf(source))) return null;
      final bytes = await _bytesOf(source);
      if (bytes == null) return null;
      return await playSound(
        deviceId: onDefault ? null : output,
        bytes: bytes,
        volume: volume,
        maxMs: SoundboardPlay.maxPlayback.inMilliseconds,
      );
    } catch (e) {
      HelperMethods.printDebug('SoundboardPlayer: on $output failed – $e');
      return null;
    }
  }

  /// Every page of an Ogg file starts with these four bytes.
  static bool _isOgg(List<int>? bytes) =>
      bytes != null &&
      bytes.length >= 4 &&
      bytes[0] == 0x4f &&
      bytes[1] == 0x67 &&
      bytes[2] == 0x67 &&
      bytes[3] == 0x53;

  /// The first bytes of [source], enough to tell an Ogg file: read alone,
  /// since every clip on the default device is asked and most are not one.
  static Future<List<int>?> _headOf(Source source) async {
    switch (source) {
      case BytesSource(:final bytes):
        return bytes;
      case DeviceFileSource(:final path):
        final file = await File(path).open();
        try {
          return await file.read(4);
        } finally {
          await file.close();
        }
      default:
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
    if (cue != null) await _stopCue(cue);
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
///
/// Held from before it is audible, with neither filled in yet, so the place
/// it takes counts while its bytes are still being decoded.
class _Clip {
  final String id;
  AudioPlayer? player;
  int? cue;

  _Clip(this.id);
}
