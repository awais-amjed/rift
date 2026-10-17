import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../common/loading_dots.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// The uppercase divider above a group of rows — TEXT, VOICE, ONLINE — with
/// the group's own "add" affordance on the right where one exists.
///
/// Creating a channel belongs here rather than in a toolbar: the button that
/// makes a thing should sit with the things it makes.
class SectionHeader extends StatelessWidget {
  final String label;

  /// Shows a trailing "+" when set. Null hides it — most callers can't create.
  final VoidCallback? onAdd;

  final String addTooltip;

  /// Still finding out what goes under it: who is online, who is in a call.
  /// Without it an empty group and one not yet heard from look the same.
  final bool busy;

  const SectionHeader({
    super.key,
    required this.label,
    this.onAdd,
    this.addTooltip = 'Create',
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 16, 9, 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              spacing: 8,
              children: [
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.sectionLabel.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
                ),
                if (busy)
                  LoadingDots(color: themeState.textQuaternary, dotSize: 3),
              ],
            ),
          ),
          if (onAdd != null) _AddButton(onTap: onAdd!, tooltip: addTooltip),
        ],
      ),
    );
  }
}

/// Small enough to live here: it exists only to give the "+" a hit area and a
/// hover colour without inheriting IconButton's padding.
class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;

  const _AddButton({required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;

    return Tooltip(
      message: tooltip,
      waitDuration: K.tooltipDelay,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(K.radiusRow),
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.add_rounded,
            size: K.iconInline,
            color: themeState.textQuaternary,
          ),
        ),
      ),
    );
  }
}
