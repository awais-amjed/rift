import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';

/// A quiet explanatory card for an empty or unconfigured state.
///
/// Bordered rather than bare text: an empty list should look like a place
/// where something will go, not like a rendering failure.
class HintCard extends StatelessWidget {
  /// Null for a card that is purely a note. An icon earns its place when the
  /// card stands in for missing content; beside one quiet sentence in a list
  /// that already has icons down its left edge, it is only clutter.
  final IconData? icon;

  final String text;

  /// Optional call to action under the text.
  final Widget? action;

  const HintCard({super.key, this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: themeState.bgHover,
            borderRadius: BorderRadius.circular(K.radiusButton),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 9,
                children: [
                  if (icon != null)
                    Icon(icon, size: 15, color: themeState.textQuaternary),
                  Expanded(
                    child: Text(
                      text,
                      style: AppText.secondary.copyWith(
                        height: 1.5,
                        color: themeState.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              if (action != null) ...[const SizedBox(height: 10), action!],
            ],
          ),
        );
      },
    );
  }
}
