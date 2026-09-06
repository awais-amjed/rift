import 'package:flutter/material.dart';

import '../../logic/services/central_handle.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import 'app_text_field.dart';

/// The handle field, with its rule underneath.
///
/// One widget for the three sign-up forms, so the hint, the rule and the
/// wording agree with the claim panel on the DM tab — which is the same
/// question, asked later, of somebody who skipped it here.
class HandleField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;

  const HandleField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onChanged,
    this.onEditingComplete,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: controller,
          label: 'Handle',
          hint: 'your_handle',
          enabled: enabled,
          onChanged: onChanged,
          onEditingComplete: onEditingComplete,
        ),
        const SizedBox(height: 6),
        Text(
          '${CentralHandle.rule} People find you by it.',
          style: AppText.secondary.copyWith(color: themeState.textQuaternary),
        ),
      ],
    );
  }
}
