import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../data/enums/ducking_preference.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// The four choices in Windows' Sound window, drawn the way that window lists
/// them, with the one to pick marked — so the person knows what they are
/// looking for before the window opens, in words they will find there.
class WindowsDuckingChoices extends StatelessWidget {
  /// What Windows is set to now, marked "Now".
  final DuckingPreference? current;

  const WindowsDuckingChoices({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'When Windows detects communications activity:',
            style: AppText.meta.copyWith(color: theme.textTertiary),
          ),
          const SizedBox(height: 6),
          for (final choice in DuckingPreference.values)
            _Choice(choice: choice, isCurrent: choice == current),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final DuckingPreference choice;
  final bool isCurrent;

  const _Choice({required this.choice, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final pick = choice == DuckingPreference.off;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: pick ? theme.channelActiveBg : null,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(
          color: pick ? theme.channelActiveBorder : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCurrent
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: K.iconRow,
            color: pick ? theme.accentBright : theme.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              choice.windowsLabel,
              style: (pick ? AppText.secondaryStrong : AppText.secondary)
                  .copyWith(
                    color: pick ? theme.textPrimary : theme.textSecondary,
                  ),
            ),
          ),
          if (pick)
            _Tag(label: 'Choose this', color: theme.accentBright)
          else if (isCurrent)
            _Tag(label: 'Now', color: theme.textTertiary),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) =>
      Text(label, style: AppText.meta.copyWith(color: color));
}
