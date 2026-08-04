import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';

/// Themed text field used throughout the app.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool obscureText;
  final bool enabled;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final bool autofocus;

  const AppTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.obscureText = false,
    this.enabled = true,
    this.keyboardType,
    this.onChanged,
    this.onEditingComplete,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.read<ThemeCubit>().state;
    final borderColor = themeState.borderElevated;
    // A focused field is ringed in a *tinted* accent, not the flat accent —
    // full strength reads as an error state next to the quiet surfaces around
    // it.
    final focusColor = themeState.primary.withValues(alpha: 0.55);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!.toUpperCase(),
            style: AppText.sectionLabel.copyWith(
              fontSize: 10.5,
              letterSpacing: 1.2,
              color: themeState.textTertiary,
            ),
          ),
          const SizedBox(height: 7),
        ],
        TextField(
          controller: controller,
          obscureText: obscureText,
          enabled: enabled,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onEditingComplete: onEditingComplete,
          autofocus: autofocus,
          style: AppText.body.copyWith(
            fontSize: 13.5,
            color: themeState.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppText.body.copyWith(
              fontSize: 13.5,
              color: themeState.textQuaternary,
            ),
            filled: true,
            fillColor: themeState.bgTertiary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
              borderSide: BorderSide(color: focusColor, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
              borderSide: BorderSide(color: borderColor.withValues(alpha: 0.5)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }
}
