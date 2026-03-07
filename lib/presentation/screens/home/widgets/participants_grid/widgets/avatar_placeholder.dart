import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/custom_colors.dart';

/// Avatar placeholder shown when participant has no video
class AvatarPlaceholder extends StatelessWidget {
  final String name;
  final bool isDark;

  const AvatarPlaceholder({
    super.key,
    required this.name,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Center(
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: isDark
                  ? CustomColors.bgTertiaryDark
                  : CustomColors.bgActiveLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: themeState.borderPrimary),
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: themeState.textTertiary,
              ),
            ),
          ),
        );
      },
    );
  }
}
