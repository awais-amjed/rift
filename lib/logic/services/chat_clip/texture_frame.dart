import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The picture a runner or player texture holds now, drawn into a scene of
/// its own at [side] × [side] and read back as RGBA; null where it could not
/// be. Stretched to the square, not cropped, which is how the image-safety
/// model wants a picture. [quarterTurns] turns it the way the card draws it.
///
/// A scene of its own, rather than a copy of what the card shows, so it
/// reads the same picture wherever the video is drawn (the card or the
/// viewer page) and costs one small draw on the raster thread.
Future<ByteData?> textureFrame(
  int textureId,
  int side, {
  int quarterTurns = 0,
}) async {
  final size = side.toDouble();
  final builder = ui.SceneBuilder();
  final turned = quarterTurns % 4 != 0;
  if (turned) {
    final half = size / 2;
    final angle = quarterTurns * math.pi / 2;
    final c = math.cos(angle), s = math.sin(angle);
    // About the middle: move it to the origin, turn, move it back.
    builder.pushTransform(
      Float64List.fromList([
        c, s, 0, 0, //
        -s, c, 0, 0, //
        0, 0, 1, 0, //
        half - c * half + s * half, half - s * half - c * half, 0, 1,
      ]),
    );
  }
  builder.addTexture(textureId, width: size, height: size);
  if (turned) builder.pop();
  final scene = builder.build();
  ui.Image? image;
  try {
    image = await scene.toImage(side, side);
    return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    scene.dispose();
  }
}
