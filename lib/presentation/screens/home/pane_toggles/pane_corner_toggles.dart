import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../responsive/shell_scope.dart';
import 'show_members_button.dart';
import 'show_sidebar_button.dart';

/// The two show buttons for a pane that has no header — the voice area
/// before a call, while one connects, when one fails.
///
/// Sat where a header's buttons would be, so they are in the same place as in
/// every other pane rather than drawing a header bar around nothing. A
/// [Stack] child laid over the pane; nothing at all on a phone, whose pages
/// have their own headers.
class PaneCornerToggles extends StatelessWidget {
  const PaneCornerToggles({super.key});

  /// Where a header's buttons sit: centred in its height, at its padding.
  static const double _top = (K.paneHeaderHeight - 32) / 2;

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact) return const SizedBox.shrink();
    return Stack(
      children: [
        if (ShowSidebarButton.shows(context))
          const Positioned(top: _top, left: 18, child: ShowSidebarButton()),
        if (ShowMembersButton.shows(context))
          const Positioned(top: _top, right: 10, child: ShowMembersButton()),
      ],
    );
  }
}
