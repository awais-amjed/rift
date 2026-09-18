import 'package:flutter/material.dart';

/// Content centred in the space it is given, scrolling when it does not fit.
///
/// The scroll view itself always fills that space, and the centring and the
/// [maxWidth] happen inside it. The obvious way round — `Center` around a
/// `SingleChildScrollView` — shrinks the scroll view to the width of what it
/// holds, and its scrollbar then runs down the middle of the window beside a
/// narrow column instead of down the window's edge.
class CenteredScrollView extends StatelessWidget {
  final Widget child;

  /// Inside the scroll view, so the content scrolls under it rather than being
  /// clipped by it. Uneven vertical padding moves where "centred" is.
  final EdgeInsets padding;

  /// The widest [child] may be. Null lets it be as wide as the space.
  final double? maxWidth;

  const CenteredScrollView({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = maxWidth;
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: _fill(constraints.maxWidth, padding.horizontal),
              minHeight: _fill(constraints.maxHeight, padding.vertical),
            ),
            child: Center(
              child: width == null
                  ? child
                  : ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width),
                      child: child,
                    ),
            ),
          ),
        );
      },
    );
  }

  /// What is left of [extent] after [padding], or nothing when the extent is
  /// unbounded — inside another scrollable there is no space to fill.
  static double _fill(double extent, double padding) =>
      extent.isFinite ? (extent - padding).clamp(0, extent) : 0;
}
