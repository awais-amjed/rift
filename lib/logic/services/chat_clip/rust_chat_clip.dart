import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../data/repositories/blob/blob_reader.dart';
import '../../../src/rust/api/clips.dart';
import '../../helper_methods.dart';
import '../runner_textures.dart';
import 'chat_clip.dart';

/// A chat video played by Rust into a runner texture (`rust/src/clips`):
/// GStreamer on Linux, the Media Engine on Windows. The player asks for the
/// file a block at a time, on its own thread (`ClipRead`), and is answered
/// from the clip's [BlobReader].
class RustChatClip implements ChatClip {
  /// What Flutter's `Texture` draws.
  final int textureId;

  final StreamController<ClipEvent> _events;
  final BlobReader _file;

  RustChatClip._(this.textureId, this._events, this._file);

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
  // ignore: cancel_subscriptions
  static StreamSubscription<ClipRead>? _reading;
  static final Map<int, StreamController<ClipEvent>> _open = {};
  static final Map<int, BlobReader> _files = {};

  static void _listen() {
    _listening ??= clipEventStream().listen((event) {
      _open[event.texture.toInt()]?.add(event);
    });
    _reading ??= clipReadStream().listen((read) => unawaited(_answer(read)));
  }

  /// What a player asked for, from its clip's file. Nothing for a clip that
  /// has closed: Rust has stopped waiting.
  static Future<void> _answer(ClipRead read) async {
    final file = _files[read.texture.toInt()];
    if (file == null) return;
    try {
      final bytes = await file.readFully(read.offset.toInt(), read.length);
      await clipAnswer(
        texture: read.texture,
        request: read.request,
        bytes: bytes,
      );
    } catch (e) {
      if (_files[read.texture.toInt()] != file) return;
      // Not the error itself, which may carry the file's address.
      final why = e is FormatException ? e.message : '${e.runtimeType}';
      HelperMethods.printDebug('[ChatClip] read failed: $why');
      await clipRefuse(
        texture: read.texture,
        request: read.request,
        reason: why,
      );
    }
  }

  @override
  Stream<ClipEvent> get events => _events.stream;

  /// GStreamer and Media Foundation wait inside a read without a word, so the card watches the clock.
  @override
  ValueListenable<bool>? get waiting => null;

  /// [ChatClip.open], in a runner texture. [output] is WebRTC's id for the
  /// output.
  static Future<({ChatClip? clip, String? error})> open(
    BlobReader file, {
    String? output,
  }) async {
    _listen();
    final texture = await RunnerTextures.create();
    if (texture == null) {
      await file.close();
      return (clip: null, error: 'No surface to draw on');
    }
    // Not a broadcast: what the player says before the card listens (a
    // file Windows cannot read fails at once) waits for it.
    final events = StreamController<ClipEvent>();
    _open[texture.id] = events;
    // Before it opens: opening reads the file.
    _files[texture.id] = file;
    try {
      await clipOpen(
        length: BigInt.from(file.length),
        texture: BigInt.from(texture.id),
        markFrame: BigInt.from(texture.mark),
        output: output,
      );
      return (clip: RustChatClip._(texture.id, events, file), error: null);
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] open: $e');
      _open.remove(texture.id);
      _files.remove(texture.id);
      await file.close();
      await events.close();
      await RunnerTextures.dispose(texture.id);
      return (clip: null, error: '$e');
    }
  }

  /// The names posters read under, apart from every texture's.
  static int _posters = 1 << 62;

  /// [ChatClip.poster]: the player reads [file] as a clip's does, under a
  /// name of its own, only as far as its first picture.
  static Future<Uint8List?> poster(BlobReader file, {int longest = 880}) async {
    _listen();
    final name = _posters++;
    _files[name] = file;
    try {
      return await clipPoster(
        length: BigInt.from(file.length),
        name: BigInt.from(name),
        longest: longest,
      );
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] poster: $e');
      return null;
    } finally {
      _files.remove(name);
      await file.close();
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

  /// Stops it, lets the file go, then the texture.
  @override
  Future<void> close() async {
    await _quietly('close', () => clipClose(texture: _texture));
    _open.remove(textureId);
    _files.remove(textureId);
    await _file.close();
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
