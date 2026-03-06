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
    return GestureDetector(
      onSecondaryTap: () => _showDialog(context),
      onLongPress: () => _showDialog(context),
      child: child,
    );
  }

  void _showDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => contextMenu);
  }
}
