import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import 'app_text_field.dart';

/// One numeric operator limit, with the sentence that says what leaving it
/// blank will do.
///
/// That sentence is the whole reason this isn't just an [AppTextField]. Every
/// limit in Rift treats an empty box as a meaningful answer — "no limit" on a
/// server, "inherit the server's" on a channel — and a bare number field gives
/// no hint which of those an admin is choosing.
class LimitField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  /// What blank means here, shown under the field.
  final String helper;

  /// Trailing unit shown after the label, e.g. `MB` or `per day`.
  final String? unit;

  final bool enabled;
  final ValueChanged<String>? onChanged;

  const LimitField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.helper,
    this.unit,
    this.enabled = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: controller,
          label: unit == null ? label : '$label ($unit)',
          hint: hint,
          enabled: enabled,
          keyboardType: TextInputType.number,
          // Digits only, so a limit field can't be given a decimal point
          // or a minus sign the server would reject a round trip later.
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onChanged,
        ),
        const SizedBox(height: 5),
        Text(
          helper,
          style: AppText.secondary.copyWith(color: themeState.textQuaternary),
        ),
      ],
    );
  }
}
