import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../responsive/shell_scope.dart';
import '../theme/app_motion.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';

/// Over the widget budget and one job: the sidebar row, whose three states and
/// their motion are the point of it.
///
/// The sidebar's one row shape — channels, DM entries, anything navigable.
///
/// Three states, and they are not interchangeable: *selected* is where you
/// are, *unread* is where something happened, at rest is everything else.
/// Selected takes the accent tint and nothing else — the glyph and label
/// already carry the accent, and a border on top would signal one state four
/// ways; unread only brightens the text and adds a count, so a long list
/// still reads as one selected row among many rather than a wall of
/// highlights.
class NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isUnread;

  /// Trailing widget — an unread count, a member tally.
  final Widget? trailing;

  /// A marker stacked on the corner of [icon] — the lock on a private channel.
  ///
  /// Separate from [icon] rather than folded into it, because the glyph carries
  /// the selected-state colour animation and a private channel still has to say
  /// which *kind* of channel it is. A lock that replaced the speaker would
  /// answer the rarer question and lose the commoner one.
  final Widget? iconBadge;

  final VoidCallback? onTap;

  /// Whether tapping the row opens a page of its own on a phone, which gets a
  /// chevron to say so. A desktop's rows fill a pane beside the list instead,
  /// so it never draws one.
  final bool pushes;

  const NavRow({
    super.key,
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.isUnread = false,
    this.trailing,
    this.iconBadge,
    this.onTap,
    this.pushes = false,
  });

  /// The trailing slot, with a phone's chevron on a row that opens a page.
  Widget? _trailing(BuildContext context) {
    final trailing = this.trailing;
    if (!context.layoutMode.isCompact || !pushes) return trailing;
    final chevron = Icon(
      Icons.chevron_right_rounded,
      size: 18,
      color: context.theme.textQuaternary,
    );
    if (trailing == null) return chevron;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [trailing, chevron],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        hoverColor: themeState.bgHover,
        onTap: onTap,
        // Lights up over [AppMotion.state] rather than switching. Nothing
        // waits on it — the row you picked is already the selected one the
        // moment you press — but selection moving between two rows is the
        // app's most-repeated change, and a hard cut there is what makes a
        // sidebar feel like a list of links instead of a place.
        child: AnimatedContainer(
          duration: AppMotion.state,
          curve: AppMotion.settle,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: isSelected ? themeState.channelActiveBg : null,
          ),
          // Padding sits inside, so only the fill animates. Handed to the
          // AnimatedContainer it would animate too — and this padding is a
          // *layout mode*, not a state: a window crossing the breakpoint
          // has to be the right density on the frame it crosses, not 140ms
          // later.
          child: Padding(
            // Taller under a finger. 7 either side of a 16px icon is 32px
            // of row, which is fine for a cursor and misses badly for a
            // thumb — and these are the rows the app is navigated with.
            padding: EdgeInsets.symmetric(
              horizontal: 9,
              vertical: context.layoutMode.isCompact ? 13 : 7,
            ),
            child: Row(
              spacing: 9,
              children: [
                // The glyph and the label carry as much of the selected
                // state as the fill does, so they travel with it. A row
                // whose background fades while its text snaps looks like
                // two things happening rather than one.
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: _iconColor(themeState)),
                  duration: AppMotion.state,
                  curve: AppMotion.settle,
                  builder: (context, color, _) {
                    final glyph = Icon(icon, size: 16, color: color);
                    if (iconBadge == null) return glyph;
                    return SizedBox(
                      width: 16,
                      height: 16,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          glyph,
                          Positioned(right: -4, bottom: -3, child: iconBadge!),
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: AppMotion.state,
                    curve: AppMotion.settle,
                    // Merged onto what is already in scope, because that
                    // is what `Text(style:)` did here before. This widget
                    // *replaces* the ambient style rather than merging,
                    // and `AppText.row` inherits its metrics — so setting
                    // it bare cost the row 2px of height and dropped it
                    // under the touch minimum on a phone.
                    style: DefaultTextStyle.of(
                      context,
                    ).style.merge(_labelStyle(themeState)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: Text(label),
                  ),
                ),
                ?_trailing(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _iconColor(ThemeState themeState) {
    if (isSelected) return themeState.accentBright;
    if (isUnread) return themeState.textPrimary;
    return themeState.textQuaternary;
  }

  TextStyle _labelStyle(ThemeState themeState) {
    if (isSelected) {
      return AppText.row.copyWith(color: themeState.channelActiveText);
    }
    if (isUnread) {
      return AppText.row.copyWith(color: themeState.textPrimary);
    }
    return AppText.rowQuiet.copyWith(color: themeState.textSecondary);
  }
}
