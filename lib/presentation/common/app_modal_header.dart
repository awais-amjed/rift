import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';

/// The title strip at the top of an [AppModal]: name, optional one-line
/// explanation, optional leading icon, optional count, any header actions,
/// and the close button.
class AppModalHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? titleIcon;

  /// A figure beside the title — "Members 18" — rather than folded into the
  /// title string, so the number is set as a number and the title stays one.
  final int? count;

  /// Icon buttons between the title and the close button.
  final List<Widget> actions;

  const AppModalHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
    this.count,
    this.actions = const [],
  });

  /// The close button, and the header actions beside it.
  static const double buttonSize = 32;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final textTertiary = themeState.textTertiary;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
          child: Row(
            children: [
              if (titleIcon != null) ...[titleIcon!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A title can wrap to a second line; a channel name with no
                    // spaces in it can't, and would overflow the Expanded
                    // that's meant to be holding it. Ellipsis is the bound.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.dialogTitle.copyWith(
                              color: themeState.textPrimary,
                            ),
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$count',
                            style: AppText.figure.copyWith(color: textTertiary),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.secondary.copyWith(color: textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              ...actions,
              AppModalHeaderButton(
                icon: Icons.close,
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One icon button in a modal's header: the close, or an action beside it.
/// 32px square, the row radius, tertiary ink.
class AppModalHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const AppModalHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon, color: themeState.textTertiary, size: 18),
          constraints: const BoxConstraints.tightFor(
            width: AppModalHeader.buttonSize,
            height: AppModalHeader.buttonSize,
          ),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
            ),
          ),
        );
      },
    );
  }
}
