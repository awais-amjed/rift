import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';

/// The key itself, sized and spaced to be copied off a screen by hand.
///
/// Monospace with wide letter-spacing, and the groups kept as separate runs
/// rather than one string, because the failure this is guarding against is
/// somebody losing their place halfway through twenty-five characters.
class RecoveryKeyCard extends StatefulWidget {
  final String recoveryKey;
  final ThemeState themeState;

  const RecoveryKeyCard({
    super.key,
    required this.recoveryKey,
    required this.themeState,
  });

  @override
  State<RecoveryKeyCard> createState() => _RecoveryKeyCardState();
}

class _RecoveryKeyCardState extends State<RecoveryKeyCard> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeState;
    final groups = widget.recoveryKey.split('-');

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: theme.bgTertiary,
            border: Border.all(color: theme.borderPrimary),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 10,
            children: [
              for (final group in groups)
                Text(
                  group,
                  style: AppText.body.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.4,
                    color: theme.textPrimary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _copy,
          icon: Icon(
            _copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 15,
            color: _copied ? theme.accentBright : theme.textTertiary,
          ),
          label: Text(
            _copied ? 'Copied' : 'Copy to clipboard',
            style: AppText.secondary.copyWith(
              fontSize: 12.5,
              color: _copied ? theme.accentBright : theme.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
