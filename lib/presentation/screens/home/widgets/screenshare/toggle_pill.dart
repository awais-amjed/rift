import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

/// A toggle pill widget for on/off settings
class TogglePill extends StatelessWidget {
  final bool active;

  const TogglePill({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 22,
          decoration: BoxDecoration(
            color: active ? CustomColors.primary : themeState.bgActive,
            borderRadius: BorderRadius.circular(11),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: active ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(blurRadius: 2, color: Colors.black26)],
              ),
            ),
          ),
        );
      },
    );
  }
}
