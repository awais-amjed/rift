import 'dart:typed_data';
import 'dart:ui' as ui;

/// Preparing a picked image for use as an avatar.
///
/// Avatars are stored **unencrypted** (migration 014) and are fetched by every
/// member who renders a message, so the cost of a large file is paid over and
/// over. Everything here exists to keep that cost small and predictable:
/// the source is downscaled and re-encoded before upload, so a 12 MB phone
/// photo becomes a couple of hundred KB regardless of what the user picked.
class AvatarImage {
  const AvatarImage._();

  /// Longest edge of the stored image. Avatars render at 34 logical pixels at
  /// most; 256 leaves headroom for high-DPI displays without storing a photo.
  static const int maxDimension = 256;

  /// Hard ceiling on what we'll even attempt to decode, matching the bucket's
  /// limit. Rejected before reading rather than after, so a huge file can't
  /// cost a decode.
  static const int maxSourceBytes = 8 * 1024 * 1024;

  /// Image types worth accepting. Anything else is rejected up front rather
  /// than failing later inside the codec with an opaque error.
  static const Set<String> supportedMimes = {
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/gif',
    'image/bmp',
  };

  static bool isSupportedMime(String? mime) =>
      mime != null && supportedMimes.contains(mime.toLowerCase());

  /// Whether [bytes] is small enough to bother decoding.
  static bool isAcceptableSize(int byteLength) =>
      byteLength > 0 && byteLength <= maxSourceBytes;

  /// The target size for a source of [width]×[height], preserving aspect ratio
  /// and never scaling *up* — a 64px picture stays 64px rather than being
  /// blown up into a blurry 256.
  static ({int width, int height}) fitWithin(
    int width,
    int height, {
    int max = maxDimension,
  }) {
    if (width <= 0 || height <= 0) return (width: max, height: max);
    if (width <= max && height <= max) return (width: width, height: height);
    if (width >= height) {
      return (width: max, height: (height * max / width).round().clamp(1, max));
    }
    return (width: (width * max / height).round().clamp(1, max), height: max);
  }

  /// Decode, downscale and re-encode [source] as PNG.
  ///
  /// Returns null when the bytes aren't a decodable image — callers surface
  /// that as "couldn't read that image" rather than uploading something the
  /// other members can't render.
  static Future<Uint8List?> prepare(Uint8List source) async {
    if (!isAcceptableSize(source.length)) return null;
    try {
      final descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(source),
      );
      final target = fitWithin(descriptor.width, descriptor.height);
      final codec = await descriptor.instantiateCodec(
        targetWidth: target.width,
        targetHeight: target.height,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      descriptor.dispose();
      codec.dispose();
      if (data == null) return null;
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
