import 'package:equatable/equatable.dart';

import '../../data/classes/panel_block.dart';

/// A live panel folded to one line in the bar above the message box.
///
/// Read out of the panel's own blocks, so every bot gets a folded line
/// without new vocabulary (BOTS.md §5): the first picture as a cover, the
/// first `fields` block's first two values as its two lines — song and
/// artist, for a player — else the first heading, the first `actions`
/// block's buttons that are not `danger`, and the first progress bar.
class PanelSummary extends Equatable {
  /// The first `image` block, or null.
  final PanelBlock? cover;
  final String title;
  final String? subtitle;

  /// At most [maxButtons], none of them `danger`: a Stop or a Clear stays
  /// inside the opened panel, a tap further from a slip.
  final List<PanelAction> buttons;

  /// 0–1, or null without a progress block.
  final double? progress;

  static const int maxButtons = 2;

  const PanelSummary({
    required this.cover,
    required this.title,
    required this.subtitle,
    required this.buttons,
    required this.progress,
  });

  static PanelSummary of(Panel panel) {
    PanelBlock? first(PanelBlockType type) =>
        panel.blocks.where((b) => b.type == type).firstOrNull;

    final fields = first(PanelBlockType.fields)?.fields ?? const [];
    final heading = first(PanelBlockType.heading)?.text;
    return PanelSummary(
      cover: first(PanelBlockType.image),
      title: fields.isNotEmpty ? fields.first.value : (heading ?? ''),
      subtitle: fields.length > 1 ? fields[1].value : null,
      buttons: [
        for (final action
            in first(PanelBlockType.actions)?.actions ?? const <PanelAction>[])
          if (action.style != PanelButtonStyle.danger) action,
      ].take(maxButtons).toList(),
      progress: first(PanelBlockType.progress)?.value,
    );
  }

  /// [panel] opened in the bar, cut in two: its last buttons and menus, which
  /// the bar keeps in sight below the part that scrolls, and the rest. Only a
  /// run at the very end: a row in the middle belongs with the words around
  /// it. A player's cover alone is taller than the bar on most screens, and
  /// Stop sat under it.
  static (Panel body, List<PanelBlock> controls) pinControls(Panel panel) {
    final blocks = panel.blocks;
    var cut = blocks.length;
    while (cut > 0 &&
        (blocks[cut - 1].type == PanelBlockType.actions ||
            blocks[cut - 1].type == PanelBlockType.select)) {
      cut--;
    }
    if (cut == blocks.length) return (panel, const []);
    return (
      Panel(blocks: blocks.sublist(0, cut), live: panel.live),
      blocks.sublist(cut),
    );
  }

  @override
  List<Object?> get props => [cover, title, subtitle, buttons, progress];
}
