import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/app_button.dart';

/// Starts watching a screen share: the app's secondary button, over the tile.
///
/// It used to be its own black-70% pill with its own radius and elevation —
/// the only button in the app not drawn like the others. Then the primary
/// accent, which outshouted the name, quality and watchers around it on a
/// tile that is pressed anywhere to watch anyway.
class WatchStreamButton extends StatelessWidget {
  final VoidCallback onTap;

  const WatchStreamButton({super.key, required this.onTap});

  /// Below this a tile gets the short label and a shorter button.
  static const _compactHeight = 150.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // An unopened stream is a tile about the size of a person's, so in a
        // busy call it is small. Still centred: the name badge sits over it
        // the way it sits over an avatar.
        final compact = constraints.maxHeight < _compactHeight;
        final button = AppButton(
          label: compact ? 'Watch' : 'Watch stream',
          variant: AppButtonVariant.secondary,
          height: compact ? K.compactControlHeight : null,
          icon: const Icon(Icons.play_arrow_rounded, size: K.iconButton),
          onPressed: onTap,
        );
        return Center(child: button);
      },
    );
  }
}
