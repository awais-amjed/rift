import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import '../../../../data/constants.dart';

/// The "I have saved it" confirmation, as a row you press anywhere on.
///
/// A checkbox rather than a button alone because the cost of the mistake is
/// unrecoverable and lands months later. This is the last point at which the
/// truth can be told to somebody who can still act on it.
class RecoveryKeyAcknowledgement extends StatelessWidget {
  final bool value;
  final ThemeState themeState;
  final ValueChanged<bool> onChanged;

  const RecoveryKeyAcknowledgement({
    super.key,
    required this.value,
    required this.themeState,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'I have saved my recovery key somewhere safe.',
                  style: AppText.body.copyWith(color: themeState.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
