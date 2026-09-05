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

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppButton(
        label: 'Watch stream',
        icon: const Icon(
          Icons.play_arrow_rounded,
          size: 17,
          color: Colors.white,
        ),
        onPressed: onTap,
      ),
    );
  }
}
