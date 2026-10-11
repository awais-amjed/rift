import 'package:flutter/material.dart';

import '../../../../data/classes/server_member.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../popover_surface.dart';
import 'composer_menu_row_visible.dart';

/// The `/` menu: which bots are here and what they answer to.
///
/// It is filled from each bot's published manifest rather than by asking the
/// bot, for two reasons — the bot is usually asleep, and a menu that costs a
/// round trip per keystroke is not a menu (BOTS.md §4).
///
/// Discovery is the thing this design is worst at. Nobody learns a bot exists
/// by watching it talk in a channel, because it does not talk in one. So the
/// menu is not a convenience on top of the feature; it is most of how anybody
/// finds out the feature is there.
class ComposerCommandMenu extends StatelessWidget {
  /// `(bot, command name, one-line description)`, already filtered by what has
  /// been typed after the slash.
  final List<({ServerMember bot, String name, String? description})> entries;
  final void Function(ServerMember bot, String name) onSelected;

  /// The row the arrow keys are on, or null before one is pressed.
  final int? highlighted;

  const ComposerCommandMenu({
    super.key,
    required this.entries,
    required this.onSelected,
    this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PopoverSurface(
        child: ConstrainedBox(
          // Tall enough for a handful, scrolling past that: this sits above a
          // composer and must not push the conversation off the screen.
          constraints: const BoxConstraints(maxHeight: 210),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: entries.length,
            itemBuilder: (context, i) => ComposerMenuRowVisible(
              active: i == highlighted,
              child: _row(context, entries[i], highlighted: i == highlighted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    ({ServerMember bot, String name, String? description}) entry, {
    required bool highlighted,
  }) {
    final themeState = context.theme;
    return Material(
      // The arrow keys' row lit as the pointer lights one, so the keyboard
      // and the mouse are pointing at the same kind of thing.
      color: highlighted ? themeState.bgHover : Colors.transparent,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => onSelected(entry.bot, entry.name),
        hoverColor: themeState.bgHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            spacing: 8,
            children: [
              Text(
                '/${entry.name}',
                style: AppText.row.copyWith(
                  fontWeight: FontWeight.w600,
                  color: themeState.textPrimary,
                ),
              ),
              if (entry.description != null)
                Expanded(
                  child: Text(
                    entry.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
                )
              else
                const Spacer(),
              // Which bot answers it. Two bots can declare the same verb, and
              // the row that does not say whose it is would be a coin toss.
              Text(
                entry.bot.displayName,
                style: AppText.meta.copyWith(color: themeState.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
