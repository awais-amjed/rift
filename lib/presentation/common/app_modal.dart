import 'package:flutter/material.dart';

import '../theme/custom_colors.dart';

/// Base modal used for most dialogs in the app.
class AppModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? titleIcon;
  final Widget content;
  final List<Widget>? actions;
  final double maxWidth;

  const AppModal({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
    required this.content,
    this.actions,
    this.maxWidth = 448,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? CustomColors.bgSecondaryDark
        : CustomColors.bgSecondaryLight;
    final borderColor = isDark
        ? CustomColors.borderPrimaryDark
        : CustomColors.borderPrimaryLight;
    final textPrimary = isDark
        ? CustomColors.textPrimaryDark
        : CustomColors.textPrimaryLight;
    final textTertiary = isDark
        ? CustomColors.textTertiaryDark
        : CustomColors.textTertiaryLight;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Row(
                children: [
                  if (titleIcon != null) ...[
                    titleIcon!,
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(fontSize: 12, color: textTertiary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: textTertiary, size: 20),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: borderColor),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: content,
              ),
            ),
            // Actions
            if (actions != null) ...[
              Divider(height: 1, color: borderColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: actions!
                      .map((a) => Expanded(child: a))
                      .toList()
                      .fold<List<Widget>>([], (acc, widget) {
                        if (acc.isNotEmpty) acc.add(const SizedBox(width: 10));
                        acc.add(widget);
                        return acc;
                      }),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Helper to show an AppModal as a dialog.
Future<T?> showAppModal<T>({
  required BuildContext context,
  required Widget modal,
}) {
  return showDialog<T>(context: context, builder: (_) => modal);
}
