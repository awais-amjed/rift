import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import 'loading_dots.dart';

/// A body still loading: the dots at page size, centred in the space the
/// content will take.
///
/// [height] is for a dialog, where the content's height is roughly known and a
/// box that jumps from nothing to a list reads as the dialog resizing itself.
/// A panel or a pane fills whatever it is given and needs neither.
class LoadingBlock extends StatelessWidget {
  final double? height;
  final EdgeInsetsGeometry padding;

  const LoadingBlock({super.key, this.height, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SizedBox(
        height: height,
        child: Center(
          child: LoadingDots(color: context.theme.accentBright, dotSize: 6),
        ),
      ),
    );
  }
}
