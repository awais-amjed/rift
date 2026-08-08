import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';

/// The title strip at the top of an [AppModal]: name, optional one-line
/// explanation, optional leading icon, and the close button.
class AppModalHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? titleIcon;

  const AppModalHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final textTertiary = themeState.textTertiary;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
          child: Row(
            children: [
              if (titleIcon != null) ...[titleIcon!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.sectionTitle.copyWith(
                        fontSize: 15,
                        color: themeState.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: AppText.secondary.copyWith(
                          fontSize: 11.5,
                          color: textTertiary,
                        ),
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
        );
      },
    );
  }
}
