import 'package:flutter/material.dart';

import '../../../../data/classes/bot_suggestion.dart';
import '../../../../data/classes/server_member.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../popover_surface.dart';

/// What a bot offers while its command is typed: the songs under
/// `/play thats so tr`, picked by a click (WIRE.md §7).
///
/// Sits where the `/` menu sits and looks like it, since it is the same menu
/// one step on: that one finishes the verb, this one the rest of the line.
/// The bot's name stays on screen, because these rows are the bot's words, not
/// Rift's.
class ComposerBotSuggestions extends StatelessWidget {
  final ServerMember bot;
  final List<BotSuggestion> suggestions;

  /// Asked and not yet answered. Rows from the last answer stay up meanwhile:
  /// typing on narrows what was meant, and a menu that blinked out on every
  /// letter would be harder to click than a slightly stale one.
  final bool searching;
  final ValueChanged<BotSuggestion> onSelected;

  const ComposerBotSuggestions({
    super.key,
    required this.bot,
    required this.suggestions,
    required this.searching,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PopoverSurface(
        child: ConstrainedBox(
          // As the `/` menu: a handful, then a scroll, so the conversation
          // stays on screen.
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                child: Text(
                  searching && suggestions.isEmpty
                      ? '${bot.displayName} is searching…'
                      : suggestions.isEmpty
                      ? '${bot.displayName} found nothing'
                      : 'From ${bot.displayName}',
                  style: AppText.meta.copyWith(color: themeState.textTertiary),
                ),
              ),
              for (final suggestion in suggestions) _row(context, suggestion),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, BotSuggestion suggestion) {
    final themeState = context.theme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => onSelected(suggestion),
        hoverColor: themeState.bgHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            suggestion.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.row.copyWith(color: themeState.textPrimary),
          ),
        ),
      ),
    );
  }
}
