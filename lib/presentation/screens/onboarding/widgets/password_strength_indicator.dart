import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';

/// Visual password strength meter: four bars and, on the same row, the word
/// for what they show. One row rather than bars over a label — the label is
/// short, and a second line under every password field was 12px of height
/// spent on nothing.
class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;
    final strength = _calculateStrength(password);

    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(4, (i) {
              final active = i < strength.level;
              return Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.state,
                  curve: Curves.easeOut,
                  height: 4,
                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: active ? strength.color : theme.borderPrimary,
                    borderRadius: BorderRadius.circular(K.radiusPill),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 10),
        AnimatedSwitcher(
          duration: AppMotion.state,
          child: Text(
            strength.label,
            key: ValueKey(strength.label),
            style: AppText.secondaryStrong.copyWith(
              color: password.isEmpty ? theme.textQuaternary : strength.color,
            ),
          ),
        ),
      ],
    );
  }

  static _PasswordStrength _calculateStrength(String password) {
    if (password.isEmpty) {
      return _PasswordStrength(0, 'Enter a password', Colors.transparent);
    }

    int score = 0;

    // Length scoring
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (password.length >= 16) score++;

    // Character variety
    if (RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[A-Z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) {
      score++;
    }

    // Map score to levels (1-4)
    final level = switch (score) {
      0 || 1 => 1,
      2 || 3 => 2,
      4 || 5 => 3,
      _ => 4,
    };

    return switch (level) {
      1 => _PasswordStrength(1, 'Weak', CustomColors.error),
      2 => _PasswordStrength(2, 'Fair', CustomColors.warning),
      3 => _PasswordStrength(3, 'Strong', CustomColors.success),
      _ => _PasswordStrength(4, 'Very strong', CustomColors.success),
    };
  }
}

class _PasswordStrength {
  final int level; // 0–4
  final String label;
  final Color color;

  const _PasswordStrength(this.level, this.label, this.color);
}
