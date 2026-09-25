import 'package:flutter/material.dart';

import '../../context_menu/context_menu_item.dart';
import '../../context_menu/context_menu_overlay.dart';
import '../../context_menu/context_menu_panel.dart';
import '../../context_menu_region.dart';
import 'composer_icon_button.dart';

/// The composer's "+": attach files, or — where polls exist — a menu offering
/// that and a poll.
///
/// One button either way. Where there is only one thing to add, it does that
/// thing: a menu with a single row is a click spent confirming the only
/// choice there was.
class ComposerAddButton extends StatefulWidget {
  final bool enabled;
  final bool canAttach;
  final VoidCallback onPickFiles;

  /// Start a poll. Null where polls are not offered (DMs, a read-only seat).
  final VoidCallback? onCreatePoll;

  const ComposerAddButton({
    super.key,
    required this.enabled,
    required this.canAttach,
    required this.onPickFiles,
    this.onCreatePoll,
  });

  @override
  State<ComposerAddButton> createState() => _ComposerAddButtonState();
}

class _ComposerAddButtonState extends State<ComposerAddButton> {
  final ContextMenuOverlay _menu = ContextMenuOverlay();

  @override
  void dispose() {
    _menu.dismiss();
    super.dispose();
  }

  void _open() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final createPoll = widget.onCreatePoll!;
    _menu.show(
      context,
      _AddMenu(
        canAttach: widget.canAttach,
        onPickFiles: widget.onPickFiles,
        onCreatePoll: createPoll,
      ),
      // From the button's top edge: the composer is at the foot of the
      // window, and the menu is laid out to stay on screen from there.
      box.localToGlobal(Offset.zero),
    );
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.onCreatePoll;
    return ComposerIconButton(
      icon: Icons.add_rounded,
      tooltip: poll != null
          ? 'Add files or a poll'
          : widget.canAttach
          ? 'Attach files'
          : 'Your role cannot attach files here',
      onPressed: !widget.enabled
          ? null
          : poll != null
          ? _open
          : widget.canAttach
          ? widget.onPickFiles
          : null,
    );
  }
}

class _AddMenu extends StatelessWidget {
  final bool canAttach;
  final VoidCallback onPickFiles;
  final VoidCallback onCreatePoll;

  const _AddMenu({
    required this.canAttach,
    required this.onPickFiles,
    required this.onCreatePoll,
  });

  @override
  Widget build(BuildContext context) {
    void pick(VoidCallback action) {
      ContextMenuScope.of(context)?.call();
      action();
    }

    return ContextMenuPanel(
      children: [
        if (canAttach)
          ContextMenuItem(
            icon: Icons.attach_file_rounded,
            label: 'Upload files',
            onTap: () => pick(onPickFiles),
          ),
        ContextMenuItem(
          icon: Icons.poll_outlined,
          label: 'Create poll',
          onTap: () => pick(onCreatePoll),
        ),
      ],
    );
  }
}
