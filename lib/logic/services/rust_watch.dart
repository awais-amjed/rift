import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/watching.dart';
import '../helper_methods.dart';

/// The Rust watch connection and the runner's textures, for `LiveKitCubit`.
///
/// A watched share's picture is received on a second, receive-only connection
/// in Rust and drawn by the runner on the GPU into a texture Flutter shows,
/// instead of through the call's own connection, which turned every picture
/// into RGBA on the CPU (`docs/gpu-codecs/STEP3_PLAN.md`). Its sound comes
/// on the same connection and Rust plays it, where [playsSound]. This holds
/// the calls; which shares go this way, how loud each plays, and falling
/// back when it fails, is the cubit's.
///
/// The runner's side is the `rift/stream_texture` channel
/// (`linux/runner/stream_texture.cc`).
class RustWatch {
  const RustWatch._();

  static const MethodChannel _textures = MethodChannel('rift/stream_texture');

  /// Whether this build can watch this way: a runner with stream textures.
  /// `RIFT_WATCH_PATH=call` keeps the call's own connection, to measure the
  /// two against each other in one build.
  static final bool available =
      !kIsWeb &&
      Platform.isLinux &&
      Platform.environment['RIFT_WATCH_PATH'] != 'call';

  /// Whether Rust plays a watched share's sound, and the call's own copy is
  /// held. Where not, the call plays it as before.
  static final bool playsSound = available && watchPlaysSound();

  static Stream<WatchEvent>? _events;

  /// What the connection reports: a picture's size, or the connection lost.
  /// One stream for the app's life: the Rust side keeps one sink.
  static Stream<WatchEvent> get events =>
      _events ??= watchEventStream().asBroadcastStream();

  /// Opens the watch connection; the error in words, or null once it is open.
  static Future<String?> start({
    required String url,
    required String token,
    required Uint8List key,
    required int keyIndex,
  }) async {
    try {
      await startWatching(
        room: WatchRoom(
          livekitUrl: url,
          livekitToken: token,
          e2EeKey: key,
          e2EeKeyIndex: keyIndex,
        ),
      );
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Closes it, and every texture it was feeding stops being marked.
  static Future<void> stop() async {
    try {
      await stopWatching();
    } catch (e) {
      HelperMethods.printDebug('[RustWatch] stop: $e');
    }
  }

  /// Makes a texture and watches [identity] into it; the texture's id, or
  /// null when either half failed, with nothing left behind.
  static Future<int?> watch(String identity) async {
    final entry = watchFrameEntryPoints();
    final int textureId;
    final int mark;
    // Whether the runner can draw a picture decoded on the GPU; where Rust
    // decodes there and it cannot, watching is refused and the call's way
    // taken.
    final bool takesGpuPictures;
    try {
      final made = await _textures.invokeMapMethod<String, Object?>('create', {
        'lock': entry.lock.toInt(),
        'unlock': entry.unlock.toInt(),
      });
      final id = made?['textureId'];
      final markAt = made?['mark'];
      if (id is! int || markAt is! int) return null;
      textureId = id;
      mark = markAt;
      takesGpuPictures = made?['takesGpuPictures'] == true;
    } on MissingPluginException {
      return null;
    } catch (e) {
      HelperMethods.printDebug('[RustWatch] no texture: $e');
      return null;
    }
    try {
      await watchShare(
        shareIdentity: identity,
        texture: BigInt.from(textureId),
        markFrame: BigInt.from(mark),
        takesGpuPictures: takesGpuPictures,
      );
      return textureId;
    } catch (e) {
      HelperMethods.printDebug('[RustWatch] watch: $e');
      await _dispose(textureId);
      return null;
    }
  }

  /// Stops watching [identity], then lets its texture go: Rust no longer
  /// marks it once `unwatchShare` returns.
  static Future<void> unwatch(String identity, int textureId) async {
    try {
      await unwatchShare(shareIdentity: identity);
    } catch (e) {
      HelperMethods.printDebug('[RustWatch] unwatch: $e');
    }
    await _dispose(textureId);
  }

  /// Lets go of textures whose connection has already stopped.
  static Future<void> disposeAll(Iterable<int> textureIds) async {
    for (final id in textureIds) {
      await _dispose(id);
    }
  }

  /// A key version the call moved to.
  static Future<void> addKey(Uint8List key, int keyIndex) async {
    try {
      await setWatchKey(e2EeKey: key, e2EeKeyIndex: keyIndex);
    } catch (e) {
      HelperMethods.printDebug('[RustWatch] key: $e');
    }
  }

  /// How loud [identity]'s sound plays: what the call would play it at
  /// (`CallVolume.of`), or 0 when it would not be heard.
  static Future<void> setVolume(String identity, double volume) async {
    try {
      await setWatchVolume(shareIdentity: identity, volume: volume);
    } catch (e) {
      HelperMethods.printDebug('[RustWatch] volume: $e');
    }
  }

  /// The output chosen in settings, as WebRTC lists it; null for the default.
  static void setOutput(String? deviceId) {
    try {
      setWatchOutput(deviceId: deviceId);
    } catch (e) {
      HelperMethods.printDebug('[RustWatch] output: $e');
    }
  }

  /// Pictures off while nobody can see Rift, as the call's are.
  static Future<void> setPicturesOn(bool on) async {
    try {
      await setWatchPicturesOn(picturesOn: on);
    } catch (e) {
      HelperMethods.printDebug('[RustWatch] pictures: $e');
    }
  }

  static Future<void> _dispose(int textureId) async {
    try {
      await _textures.invokeMethod<void>('dispose', {'textureId': textureId});
    } catch (e) {
      HelperMethods.printDebug('[RustWatch] dispose: $e');
    }
  }
}
