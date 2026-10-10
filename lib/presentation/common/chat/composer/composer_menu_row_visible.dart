import 'package:flutter/widgets.dart';

/// Keeps a composer menu's row in view while the arrow keys have it.
///
/// The `/` menu and a bot's suggestions scroll past a handful of rows; moving
/// the highlight below the last visible one would otherwise leave the row
/// being picked off screen, and Enter would take something nobody could see.
class ComposerMenuRowVisible extends StatefulWidget {
  final bool active;
  final Widget child;

  const ComposerMenuRowVisible({
    super.key,
    required this.active,
    required this.child,
  });

  @override
  State<ComposerMenuRowVisible> createState() => _ComposerMenuRowVisibleState();
}

class _ComposerMenuRowVisibleState extends State<ComposerMenuRowVisible> {
  @override
  void initState() {
    super.initState();
    if (widget.active) _reveal();
  }

  @override
  void didUpdateWidget(ComposerMenuRowVisible old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _reveal();
  }

  /// After layout, scrolling only as far as it takes: the row's bottom edge to
  /// the list's when moving down, its top edge to the list's when moving up.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
