import 'package:flutter/material.dart';

import '../../logic/services/central_handle.dart';
import '../theme/app_text.dart';
import '../theme/custom_colors.dart';
import '../theme/theme_context.dart';
import 'app_text_field.dart';

/// The handle field, with its rule underneath.
///
/// One widget for every place the handle is asked for — the sign-up forms, the
/// claim panel on the DM tab and the rename dialog — so the hint, the rule,
/// the wording and what the box will accept cannot disagree. They did: two of
/// those sites drew their own `AppTextField`, and none of the three folded
/// anything, so `AB Cd!` sat in a box under a line saying handles are a–z, 0–9
/// and underscore, and was refused only once the form was submitted.
class HandleField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool autofocus;

  /// Shown under the rule. The claim panel and the rename dialog report a
  /// refusal from central — a taken handle — which is not something the rule
  /// can predict.
  final String? error;

  /// Hidden when this field is not the whole question being asked; the sign-up
  /// forms label every field, the claim panel asks in a sentence above.
  final bool showLabel;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;

  const HandleField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.autofocus = false,
    this.error,
    this.showLabel = true,
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
          label: showLabel ? 'Handle' : null,
          hint: 'your_handle',
          enabled: enabled,
          autofocus: autofocus,
          inputFormatters: CentralHandle.inputFormatters,
          maxLength: CentralHandle.maxLength,
          onChanged: onChanged,
          onEditingComplete: onEditingComplete,
        ),
        const SizedBox(height: 6),
        Text(
          '${CentralHandle.rule} People find you by it.',
          style: AppText.secondary.copyWith(color: themeState.textQuaternary),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: AppText.secondary.copyWith(color: CustomColors.error),
          ),
        ],
      ],
    );
  }
}
