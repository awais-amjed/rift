import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Paints its child with its top-left corner on a whole device pixel.
///
/// Text lands on whole pixels wherever it is laid out, but a shape does not:
/// a badge centred in a row whose height came out at 34.5 drew its pill half
/// a pixel down with blurred edges, while the count inside snapped back up,
/// so the count sat half a pixel off the pill's middle. Moving the whole
/// thing onto the pixel grid keeps the shape and its text together. The
/// shift is under half a pixel, so layout and hit testing stay where they
/// were.
class PixelSnap extends SingleChildRenderObjectWidget {
  const PixelSnap({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPixelSnap(MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(BuildContext context, RenderPixelSnap renderObject) {
    renderObject.ratio = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderPixelSnap extends RenderProxyBox {
  RenderPixelSnap(this._ratio);

  double _ratio;
  set ratio(double value) {
    if (value == _ratio) return;
    _ratio = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    // Snapped on the screen, not in the layer, which may itself sit between
    // pixels. It holds until the next paint: a list scrolled by a fraction
    // moves its layer without repainting what is in it.
    final screen = localToGlobal(Offset.zero) * _ratio;
    final snapped = Offset(
      screen.dx.roundToDouble(),
      screen.dy.roundToDouble(),
    );
    context.paintChild(child!, offset + (snapped - screen) / _ratio);
  }
}
