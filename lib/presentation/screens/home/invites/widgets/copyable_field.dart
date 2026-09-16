import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// A value meant to be copied exactly — an invite link — with the button that
/// copies it.
///
/// Mono at full contrast: an invite code is exactly what mono is for, and
/// tertiary ink on the one string somebody is about to read aloud was the
/// wrong place to be quiet. The button is a real button beside the field
/// rather than an icon inside it; "Copied" is the button's own label for a
/// moment, where the eye already is.
class CopyableField extends StatelessWidget {
  final String? value;
  final String? placeholder;
  final bool copied;
  final VoidCallback? onCopy;

  const CopyableField({
    super.key,
    this.value,
    this.placeholder,
    required this.copied,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: Container(
            height: K.fieldHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: theme.bgTertiary,
              borderRadius: BorderRadius.circular(K.radiusRow),
              border: Border.all(color: theme.borderPrimary),
            ),
            child: value != null
                ? Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.code.copyWith(color: theme.textPrimary),
                  )
                : Text(
                    placeholder ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.secondary.copyWith(
                      color: theme.textTertiary,
                    ),
                  ),
          ),
        ),
        if (onCopy != null)
          AppButton(
            label: copied ? 'Copied' : 'Copy',
            variant: AppButtonVariant.secondary,
            icon: Icon(
              copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 14,
              color: theme.textSecondary,
            ),
            onPressed: value == null ? null : onCopy,
          ),
      ],
    );
  }
}
