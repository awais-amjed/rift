import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../responsive/shell_scope.dart';
import '../theme/app_motion.dart';
import '../theme/app_text.dart';

/// The sidebar's one row shape — channels, DM entries, anything navigable.
///
/// Three states, and they are not interchangeable: *selected* is where you
/// are, *unread* is where something happened, at rest is everything else.
/// Selected takes the accent gradient with a ring; unread only brightens the
/// text and adds a count, so a long list still reads as one selected row
/// among many rather than a wall of highlights.
class NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isUnread;

  /// Trailing widget — an unread count, a member tally.
  final Widget? trailing;

  final VoidCallback? onTap;

  const NavRow({
    super.key,
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.isUnread = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final radius = BorderRadius.circular(K.radiusRow);

        return Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
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
                // The gradient fades left-to-right so the row reads as lit
                // from its leading edge, not filled like a button.
                gradient: isSelected ? themeState.activeRowGradient : null,
                border: isSelected
                    ? Border.all(color: themeState.channelActiveBorder)
                    : null,
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
                      builder: (context, color, _) =>
                          Icon(icon, size: 16, color: color),
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
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
