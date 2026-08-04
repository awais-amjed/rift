import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/app_text.dart';

/// Error view shown when connection fails.
class ErrorView extends StatelessWidget {
  final String error;

  const ErrorView({super.key, required this.error});

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
                const Text('⚠️', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                Text(
                  'Connection Error',
                  style: AppText.dialogTitle.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: themeState.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    error,
                    style: AppText.rowQuiet.copyWith(
                      fontSize: 14,
                      color: CustomColors.error,
                    ),
                    textAlign: TextAlign.center,
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
