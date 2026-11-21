import '../../helper_methods.dart';

/// Where a clip's preview plays: the call's output, as WebRTC names it.
abstract final class ClipOutput {
  /// [play] on [output], or on the system's default (a null device) when
  /// there is no such output any more. The call itself falls back the same
  /// way, and a preview on the wrong device is better than none, as with the
  /// soundboard (`SoundboardPlayer`). WebRTC's own "default: …" entry is the
  /// system default already.
  static Future<T> play<T>(
    String? output,
    Future<T> Function(String? deviceId) play,
  ) async {
    final onDefault =
        output == null || output.isEmpty || output.startsWith('default: ');
    if (onDefault) return play(null);
    try {
      return await play(output);
    } catch (e) {
      HelperMethods.printDebug('[Clips] preview on $output failed – $e');
      return play(null);
    }
  }
}
