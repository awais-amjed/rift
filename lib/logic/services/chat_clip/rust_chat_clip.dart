import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../src/rust/api/clips.dart';
import '../../helper_methods.dart';
import '../runner_textures.dart';
import 'chat_clip.dart';

/// A chat video played by Rust from memory into a runner texture
/// (`rust/src/clips`): GStreamer on Linux, the Media Engine on Windows.
class RustChatClip implements ChatClip {
  /// What Flutter's `Texture` draws.
  final int textureId;

  final StreamController<ClipEvent> _events;

  RustChatClip._(this.textureId, this._events);

  /// Whether the library has a player here. Not on Windows N without its
  /// media pack.
  static bool available() {
    try {
      return clipsAvailable();
    } catch (_) {
      return false;
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

  @override
  Stream<ClipEvent> get events => _events.stream;

  /// [ChatClip.open], in a runner texture. [output] is WebRTC's id for the
  /// output.
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
      return (clip: RustChatClip._(texture.id, events), error: null);
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] open: $e');
      _open.remove(texture.id);
      await events.close();
      await RunnerTextures.dispose(texture.id);
      return (clip: null, error: '$e');
    }
  }

  static Future<Uint8List?> poster(Uint8List video, {int longest = 880}) async {
    try {
      return await clipPoster(bytes: video, longest: longest);
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] poster: $e');
      return null;
    }
  }

  BigInt get _texture => BigInt.from(textureId);

  @override
  Widget picture() => Texture(textureId: textureId);

  @override
  Future<bool> play() => _quietly('play', () => clipPlay(texture: _texture));

  @override
  Future<void> pause() => _quietly('pause', () => clipPause(texture: _texture));

  @override
  Future<void> seek(Duration to) => _quietly(
    'seek',
    () => clipSeek(
      texture: _texture,
      positionMs: BigInt.from(to.inMilliseconds.clamp(0, 1 << 40)),
    ),
  );

  @override
  Future<void> setVolume(double volume) => _quietly(
    'volume',
    () => clipSetVolume(texture: _texture, volume: volume),
  );

  @override
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
  @override
  Future<void> close() async {
    await _quietly('close', () => clipClose(texture: _texture));
    _open.remove(textureId);
    await _events.close();
    await RunnerTextures.dispose(textureId);
  }

  /// Whether [call] went through; a failure is logged, not thrown.
  Future<bool> _quietly(String what, Future<void> Function() call) async {
    try {
      await call();
      return true;
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] $what: $e');
      return false;
    }
  }
}
