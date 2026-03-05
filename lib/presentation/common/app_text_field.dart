import 'package:flutter/material.dart';

import '../theme/custom_colors.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? CustomColors.borderPrimaryDark
        : CustomColors.borderPrimaryLight;
    final focusColor = CustomColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: isDark
                  ? CustomColors.textTertiaryDark
                  : CustomColors.textTertiaryLight,
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          obscureText: obscureText,
          enabled: enabled,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onEditingComplete: onEditingComplete,
          autofocus: autofocus,
          style: TextStyle(
            fontSize: 14,
            color: isDark
                ? CustomColors.textPrimaryDark
                : CustomColors.textPrimaryLight,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 14,
              color: isDark
                  ? CustomColors.textQuaternaryDark
                  : CustomColors.textQuaternaryLight,
            ),
            filled: true,
            fillColor: isDark
                ? CustomColors.bgTertiaryDark
                : CustomColors.bgTertiaryLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: focusColor, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor.withOpacity(0.5)),
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
