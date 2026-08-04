import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';

/// View shown when no voice channel is selected.
class NoChannelView extends StatelessWidget {
  const NoChannelView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          color: themeState.bgSecondary,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎙️', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                Text(
                  'No Channel Selected',
                  style: AppText.dialogTitle.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: themeState.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a voice channel from the sidebar to join',
                  style: AppText.rowQuiet.copyWith(
                    fontSize: 14,
                    color: themeState.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
