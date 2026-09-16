import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One row in the switcher: a mark, a name, a line saying what is going on
/// there, and whatever wants your attention at the end.
///
/// The selected row takes the same tint and ring as every other selection in
/// the app. [boxed] gives an unselected row a quiet card too — Home's, which
/// stands apart from the list of servers under it.
class SwitcherRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final Widget subtitle;
  final Widget? trailing;
  final bool selected;
  final bool boxed;
  final VoidCallback onTap;

  static const double leadingSize = 36;

  const SwitcherRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.selected = false,
    this.boxed = false,
  });

  static TextStyle subtitleStyle(ThemeState theme) =>
      AppText.label.copyWith(color: theme.textTertiary);

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusCard);
    final fill = selected
        ? theme.channelActiveBg
        : (boxed ? theme.bgHover : Colors.transparent);
    final border = selected
        ? theme.channelActiveBorder
        : (boxed ? theme.borderElevated : Colors.transparent);

    return Material(
      color: fill,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: border),
          ),
          child: Row(
            spacing: 11,
            children: [
              leading,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.strong.copyWith(
                        color: selected
                            ? theme.channelActiveText
                            : theme.textPrimary,
                      ),
                    ),
                    subtitle,
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
