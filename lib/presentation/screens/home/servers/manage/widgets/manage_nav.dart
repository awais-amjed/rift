import 'package:flutter/material.dart';

import '../../../../../common/nav_row.dart';
import '../../../../../theme/theme_context.dart';

/// A page-per-concern dialog's left-hand nav: one row per page the viewer may
/// see.
///
/// The settings screen's rows, so a page picker reads the same wherever it
/// is. Generic over the page enum because two dialogs share it — Manage
/// server and a channel's settings. Only the rows are here; which of them
/// exist is the caller's.
class ManageNav<T> extends StatelessWidget {
  final List<T> tabs;
  final T? active;
  final ValueChanged<T> onSelected;
  final String Function(T tab) labelOf;
  final IconData Function(T tab) iconOf;

  /// The whole width, as a phone's list of pages rather than a column beside
  /// one.
  final bool expand;

  const ManageNav({
    super.key,
    required this.tabs,
    required this.active,
    required this.onSelected,
    required this.labelOf,
    required this.iconOf,
    this.expand = false,
  });

  static const double width = 196;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      width: expand ? null : width,
      color: themeState.bgSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: NavRow(
                icon: iconOf(tab),
                label: labelOf(tab),
                // Nothing is selected in a phone's list — it is the way in,
                // and the page opened is on its own screen.
                isSelected: !expand && tab == active,
                pushes: expand,
                onTap: () => onSelected(tab),
              ),
            ),
        ],
      ),
    );
  }
}
