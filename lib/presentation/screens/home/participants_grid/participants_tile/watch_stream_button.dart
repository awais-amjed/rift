import 'package:flutter/material.dart';

import '../../../../common/app_button.dart';

/// Starts watching a screen share: the app's primary button, over the tile.
///
/// It used to be its own black-70% pill with its own radius and elevation —
/// the only button in the app not drawn like the others, on the one surface
/// where it is the only thing to press.
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
          height: compact ? 32 : null,
          icon: const Icon(Icons.play_arrow_rounded, size: 17),
          onPressed: onTap,
        );
        return Center(child: button);
      },
    );
  }
}
