import 'package:flutter/material.dart';

class ContextMenuRegion extends StatelessWidget {
  final Widget child;
  final Widget contextMenu;

  const ContextMenuRegion({
    super.key,
    required this.child,
    required this.contextMenu,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder:
          (BuildContext context, MenuController controller, Widget? child) {
            return GestureDetector(
              onSecondaryTapDown: (details) {
                controller.open(position: details.localPosition);
              },
              onLongPress: () {
                controller.open();
              },
              child: child,
            );
          },
      menuChildren: [contextMenu],
      child: child,
    );
  }
}
