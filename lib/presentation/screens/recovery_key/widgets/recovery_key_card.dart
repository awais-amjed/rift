import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// The key itself, sized and spaced to be copied off a screen by hand.
///
/// Monospace with wide letter-spacing, and the groups kept as separate runs
/// rather than one string, because the failure this is guarding against is
/// somebody losing their place halfway through twenty-five characters.
class RecoveryKeyCard extends StatefulWidget {
  final String recoveryKey;
  const RecoveryKeyCard({super.key, required this.recoveryKey});

  @override
  State<RecoveryKeyCard> createState() => _RecoveryKeyCardState();
}

class _RecoveryKeyCardState extends State<RecoveryKeyCard> {
  static const double _groupSpacing = 14;
  static const double _runSpacing = 10;

  bool _copied = false;

  /// The groups split into lines of as even a length as the width allows.
  ///
  /// A plain wrap fills each line before starting the next, so on a phone
  /// five groups land as four and one — and a group alone on the last line
  /// reads as a separate thing rather than the end of the key. Working out
  /// how many lines are needed and then sharing the groups between them
  /// gives three and two instead. Every group is the same length, so one
  /// measurement covers them all.
  static List<List<String>> _balancedLines(
    List<String> groups,
    TextStyle style,
    double maxWidth,
    TextScaler scaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: groups.first, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final groupWidth = painter.width;
    painter.dispose();
    final perLine = ((maxWidth + _groupSpacing) / (groupWidth + _groupSpacing))
        .floor()
        .clamp(1, groups.length);
    final lineCount = (groups.length / perLine).ceil();
    final even = (groups.length / lineCount).ceil();
    return [
      for (var i = 0; i < groups.length; i += even)
        groups.sublist(i, (i + even).clamp(0, groups.length)),
    ];
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final groups = widget.recoveryKey.split('-');

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: theme.bgTertiary,
            border: Border.all(color: theme.borderPrimary),
            borderRadius: BorderRadius.circular(K.radiusCard),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final style = AppText.mnemonic.copyWith(color: theme.textPrimary);
              final lines = _balancedLines(
                groups,
                style,
                constraints.maxWidth,
                MediaQuery.textScalerOf(context),
              );
              return Column(
                spacing: _runSpacing,
                children: [
                  for (final line in lines)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: _groupSpacing,
                      children: [
                        // Flexible, so a group wider than the card on its
                        // own — very large system text on a phone — wraps
                        // inside its line instead of running off the edge.
                        for (final group in line)
                          Flexible(child: Text(group, style: style)),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _copy,
          icon: Icon(
            _copied ? Icons.check_rounded : Icons.copy_rounded,
            size: K.iconRow,
            color: _copied ? theme.accentBright : theme.textTertiary,
          ),
          label: Text(
            _copied ? 'Copied' : 'Copy to clipboard',
            style: AppText.secondary.copyWith(
              color: _copied ? theme.accentBright : theme.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
