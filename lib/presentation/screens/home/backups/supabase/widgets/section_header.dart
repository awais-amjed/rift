import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/app_text.dart';

/// Icon + title + description header used before each action section.
class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: theme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.row.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: AppText.secondary.copyWith(
                  fontSize: 12,
                  height: 1.5,
                  color: theme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
