import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

/// Connecting view shown while establishing LiveKit connection.
class ConnectingView extends StatelessWidget {
  const ConnectingView({super.key});

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
                const SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: CustomColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Connecting...',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: themeState.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Joining voice channel',
                  style: TextStyle(
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
