import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';

/// Visual tab indicator that appears when sidebar is hidden.
class SidebarTab extends StatelessWidget {
  const SidebarTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 12,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => context.read<AppCubit>().setIsPinned(true),
          child: BlocBuilder<ThemeCubit, ThemeState>(
            builder: (context, themeState) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                  color: themeState.bgSecondary,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                  border: Border.all(color: themeState.borderPrimary),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: themeState.isDarkTheme ? 0.3 : 0.1,
                      ),
                      blurRadius: 8,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: themeState.textSecondary,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
