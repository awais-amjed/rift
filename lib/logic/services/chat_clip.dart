import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../src/rust/api/clips.dart';
import '../helper_methods.dart';
import 'runner_textures.dart';

/// A video from the chat, played by Rust from memory into a runner texture
/// (`rust/src/clips`), with the system's own decoders.
///
/// An attachment is decrypted message content and never goes to disk, so
/// the player gets the bytes themselves. One per card that is playing; the
/// card closes it when it goes.
class ChatClip {
  /// What Flutter's `Texture` draws.
  final int textureId;

  final StreamController<ClipEvent> _events;

  ChatClip._(this.textureId, this._events);

  /// Whether this build plays a chat video itself. Where not, the card
  /// offers the file to save.
  static final bool available =
      !kIsWeb &&
      (Platform.isLinux || Platform.isWindows) &&
      _safely(clipsAvailable, false);

  static T _safely<T>(T Function() read, T otherwise) {
    try {
      return read();
    } catch (_) {
      return otherwise;
    }
  }

  /// One listener for every clip's events, routed to each by texture. It
  /// lasts the app's life: the Rust side keeps one sink.
  // ignore: cancel_subscriptions
  static StreamSubscription<ClipEvent>? _listening;
  static final Map<int, StreamController<ClipEvent>> _open = {};

  static void _listen() {
    _listening ??= clipEventStream().listen((event) {
      _open[event.texture.toInt()]?.add(event);
    });
  }

  /// What the player says about this clip: its picture's shape, the end, a
  /// failure.
  Stream<ClipEvent> get events => _events.stream;

  /// Opens [bytes], a whole video file, paused on its first picture, its
  /// sound to play on [output] (as WebRTC lists outputs; null for the
  /// default). Null, with nothing left behind, when it would not open.
  static Future<({ChatClip? clip, String? error})> open(
    Uint8List bytes, {
    String? output,
  }) async {
    _listen();
    final texture = await RunnerTextures.create();
    if (texture == null) return (clip: null, error: 'No surface to draw on');
    // Not a broadcast: what the player says before the card listens (a
    // file Windows cannot read fails at once) waits for it.
    final events = StreamController<ClipEvent>();
    _open[texture.id] = events;
    try {
      await clipOpen(
        bytes: bytes,
        texture: BigInt.from(texture.id),
        markFrame: BigInt.from(texture.mark),
        output: output,
      );
      return (clip: ChatClip._(texture.id, events), error: null);
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] open: $e');
      _open.remove(texture.id);
      await events.close();
      await RunnerTextures.dispose(texture.id);
      return (clip: null, error: '$e');
    }
  }

  /// The most a video's card downloads by itself to draw its poster, the
  /// size a file is read into memory to send at: past it the card stays
  /// dark until played.
  static const int posterMaxBytes = 16 * 1024 * 1024;

  /// [video]'s first picture as a JPEG, its longer side [longest] pixels;
  /// null where it cannot be made.
  static Future<Uint8List?> poster(Uint8List video, {int longest = 880}) async {
    try {
      return await clipPoster(bytes: video, longest: longest);
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] poster: $e');
      return null;
    }
  }

  BigInt get _texture => BigInt.from(textureId);

  Future<void> play() => _quietly('play', () => clipPlay(texture: _texture));

  Future<void> pause() => _quietly('pause', () => clipPause(texture: _texture));

  Future<void> seek(Duration to) => _quietly(
    'seek',
    () => clipSeek(
      texture: _texture,
      positionMs: BigInt.from(to.inMilliseconds.clamp(0, 1 << 40)),
    ),
  );

  /// 1 as recorded.
  Future<void> setVolume(double volume) => _quietly(
    'volume',
    () => clipSetVolume(texture: _texture, volume: volume),
  );

  /// Where it is, and how long it is, where the player knows.
  ({Duration? position, Duration? length}) time() {
    try {
      final t = clipTime(texture: _texture);
      Duration? ms(BigInt? v) =>
          v == null ? null : Duration(milliseconds: v.toInt());
      return (position: ms(t.positionMs), length: ms(t.durationMs));
    } catch (_) {
      return (position: null, length: null);
    }
  }

  /// Stops it, lets the bytes go, then the texture.
  Future<void> close() async {
    await _quietly('close', () => clipClose(texture: _texture));
    _open.remove(textureId);
    await _events.close();
    await RunnerTextures.dispose(textureId);
  }

  Future<void> _quietly(String what, Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] $what: $e');
    }
  }
}
