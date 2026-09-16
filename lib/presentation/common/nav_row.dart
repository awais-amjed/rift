import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../responsive/shell_scope.dart';
import '../theme/app_motion.dart';
import '../theme/app_text.dart';
import 'context_menu/context_menu_button.dart';
import 'unread_badge.dart';

/// The sidebar's one row shape — channels, DM entries, anything navigable.
///
/// Three states, and they are not interchangeable: *selected* is where you
/// are, *unread* is where something happened, at rest is everything else.
/// Selected takes the accent tint and nothing else — the glyph and label
/// already carry the accent, and a border on top would signal one state four
/// ways; unread only brightens the text and adds a count, so a long list
/// still reads as one selected row among many rather than a wall of
/// highlights.
///
/// [overflowMenu] is the row's right-click menu, handed over again so it can
/// also be opened from a ••• that appears while the row is hovered or
/// selected (see [ContextMenuButton]). An unread count gives way to it — a
/// count you are about to act on is noise — while a state icon such as a muted
/// bell stays, with the button after it.
class NavRow extends StatefulWidget {
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

  /// The menu the ••• opens. Null draws no button. Not on a phone, where
  /// long-press already opens it and there is no hover to reveal one.
  final Widget? overflowMenu;

  const NavRow({
    super.key,
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.isUnread = false,
    this.trailing,
    this.iconBadge,
    this.onTap,
    this.overflowMenu,
  });

  @override
  State<NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<NavRow> {
  bool _hovered = false;

  IconData get icon => widget.icon;
  String get label => widget.label;
  bool get isSelected => widget.isSelected;
  bool get isUnread => widget.isUnread;
  Widget? get iconBadge => widget.iconBadge;
  VoidCallback? get onTap => widget.onTap;

  /// The trailing slot with the overflow button worked in.
  Widget? _trailing(BuildContext context) {
    final trailing = widget.trailing;
    final menu = widget.overflowMenu;
    if (menu == null || context.layoutMode.isCompact) return trailing;

    final active = _hovered || isSelected;
    final button = ContextMenuButton(menu: menu, visible: active);
    // Badges yield, state icons don't.
    if (trailing is UnreadBadge && active) return button;
    if (trailing == null) return button;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [trailing, button],
    );
  }

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
            // The row's own hover, which the ••• follows — not a second
            // region watching the same pointer.
            onHover: widget.overflowMenu == null
                ? null
                : (hovered) => setState(() => _hovered = hovered),
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
                              Positioned(
                                right: -4,
                                bottom: -3,
                                child: iconBadge!,
                              ),
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
