import 'package:flutter/services.dart';

import '../../src/rust/api/watching.dart';
import '../helper_methods.dart';

/// A texture of the runner's that Rust feeds pictures into: a watched share
/// ([RustWatch]) or a chat video ([ChatClip]).
class RunnerTexture {
  /// The id Flutter's `Texture` widget draws.
  final int id;

  /// The runner's "a picture is waiting" function, for Rust to call.
  final int mark;

  /// Whether the runner can draw a picture decoded on the GPU.
  final bool takesGpuPictures;

  const RunnerTexture({
    required this.id,
    required this.mark,
    required this.takesGpuPictures,
  });
}

/// The runner's side of those textures, the `rift/stream_texture` channel
/// (`linux/runner/stream_texture.cc`, `windows/runner/stream_texture.cpp`).
/// The runner reads each picture from Rust's slot through the entry points
/// it is handed here.
class RunnerTextures {
  const RunnerTextures._();

  static const MethodChannel _channel = MethodChannel('rift/stream_texture');

  /// A new texture, or null where the runner has none to give.
  static Future<RunnerTexture?> create() async {
    final entry = watchFrameEntryPoints();
    try {
      final made = await _channel.invokeMapMethod<String, Object?>('create', {
        'lock': entry.lock.toInt(),
        'unlock': entry.unlock.toInt(),
      });
      final id = made?['textureId'];
      final mark = made?['mark'];
      if (id is! int || mark is! int) return null;
      return RunnerTexture(
        id: id,
        mark: mark,
        takesGpuPictures: made?['takesGpuPictures'] == true,
      );
    } on MissingPluginException {
      return null;
    } catch (e) {
      HelperMethods.printDebug('[RunnerTextures] none made: $e');
      return null;
    }
  }

  /// Lets [id] go. Call once Rust no longer marks it.
  static Future<void> dispose(int id) async {
    try {
      await _channel.invokeMethod<void>('dispose', {'textureId': id});
    } catch (e) {
      HelperMethods.printDebug('[RunnerTextures] dispose: $e');
    }
  }
}
