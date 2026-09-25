import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';

/// The sixty digits two people compare to be sure nobody is in the middle.
///
/// It is shown, not checked: this device cannot tell whether the other one
/// shows the same thing, and saying "verified" on its own word would be the
/// claim the whole exercise exists to avoid. The person reads, compares, and
/// says so — which is what [AppCubit.setVerified] records.
///
/// Digits only. A QR was drawn here until nothing could scan one, and a code
/// nobody can read is decoration on the one screen that exists to be read.
class SafetyCodeDialog extends StatelessWidget {
  /// Their name, for the sentence that says whose code this is.
  final String personName;

  /// `<tier>:<their id>` — see [AppState.verifiedCodes].
  final String person;

  final String code;

  const SafetyCodeDialog({
    super.key,
    required this.personName,
    required this.person,
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final verified = context.select<AppCubit, String?>(
      (c) => c.state.verifiedCodes[person],
    );
    final changed = verified != null && verified != code;

    return AppModal(
      title: 'Safety code',
      subtitle: 'With $personName',
      titleIcon: const Icon(Icons.verified_user_outlined, size: K.iconLarge),
      maxWidth: K.dialogWidth,
      sheetOnPhone: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (changed) ...[
            _Banner(
              icon: Icons.error_outline_rounded,
              color: CustomColors.error,
              text:
                  '$personName\'s key has changed since you verified them. '
                  'That happens when somebody reinstalls or restores a '
                  'backup — and it is also what it looks like if somebody '
                  'is intercepting. Check the new code before trusting it.',
            ),
            const SizedBox(height: 16),
          ],
          _digits(context),
          const SizedBox(height: 16),
          Text(
            'Open this same screen on $personName\'s device. If the digits '
            'match, your messages are sealed to each other and nobody else '
            'can read them. If they do not, stop and ask them somewhere '
            'else — not in this chat.',
            style: AppText.secondary.copyWith(color: theme.textTertiary),
          ),
        ],
      ),
      actions: [
        if (verified != null)
          AppButton(
            label: changed ? 'Forget' : 'Not verified',
            variant: AppButtonVariant.secondary,
            onPressed: () => context.read<AppCubit>().clearVerified(person),
          ),
        AppButton(
          label: verified != null && !changed ? 'Done' : 'They match',
          onPressed: () {
            if (verified == null || changed) {
              context.read<AppCubit>().setVerified(person, code);
            }
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  /// The code itself, four lines of three groups — the shape that survives
  /// being read aloud and being compared side by side on two screens.
  ///
  /// On its own panel and given the width: it is the only thing in here to
  /// look at, and the pair are comparing sixty digits by eye.
  Widget _digits(BuildContext context) {
    final theme = context.theme;
    final groups = SafetyCode.groups(code);
    const perLine = 3;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Column(
        children: [
          for (var i = 0; i < groups.length; i += perLine)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                groups.skip(i).take(perLine).join('   '),
                textAlign: TextAlign.center,
                // Mono, so the two screens line up column for column.
                style: AppText.code.copyWith(color: theme.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

/// A coloured note above the code — only ever about a key that changed.
class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Banner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: K.iconRow, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppText.secondary.copyWith(
                color: context.theme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
