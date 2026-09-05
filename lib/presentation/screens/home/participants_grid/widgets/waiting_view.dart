import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';

/// View shown when waiting for other participants to join.
class WaitingView extends StatelessWidget {
  const WaitingView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline,
                size: 64,
                color: themeState.textQuaternary,
              ),
              const SizedBox(height: 16),
              Text(
                'Waiting for others...',
                style: AppText.sectionTitle.copyWith(
                  color: themeState.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'re the first one here',
                style: AppText.secondary.copyWith(
                  color: themeState.textTertiary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
