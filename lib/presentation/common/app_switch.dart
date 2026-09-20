import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../responsive/shell_scope.dart';
import '../theme/app_motion.dart';

/// The app's on/off toggle.
///
/// Hand-built rather than a restyled Material [Switch]: the design pins the
/// track at 38×22 around an 18px thumb, and Material's switch geometry is
/// fixed at half again that size with no way to bring it down.
///
/// A phone gets 44×26. The row it sits in is the same height either way —
/// this is the one control in it that is *hit* rather than read, and 22px of
/// target under a thumb is a miss waiting to happen. Decided here rather
/// than passed in, because every caller would have to be told and one would
/// be forgotten.
class AppSwitch extends StatelessWidget {
  final bool value;

  /// Null renders the toggle locked — the caller dims it.
  final ValueChanged<bool>? onChanged;

  const AppSwitch({super.key, required this.value, required this.onChanged});

  static const double _trackWidth = 38;
  static const double _trackHeight = 22;
  static const double _thumbSize = 18;
  static const double _inset = 2;

  static const double _touchTrackWidth = 44;
  static const double _touchTrackHeight = 26;
  static const double _touchThumbSize = 22;

  @override
  Widget build(BuildContext context) {
    final touch = context.layoutMode.isCompact;
    final trackWidth = touch ? _touchTrackWidth : _trackWidth;
    final trackHeight = touch ? _touchTrackHeight : _trackHeight;
    final thumbSize = touch ? _touchThumbSize : _thumbSize;

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return MouseRegion(
          cursor: onChanged == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(!value),
            child: AnimatedContainer(
              duration: AppMotion.state,
              curve: Curves.easeOut,
              width: trackWidth,
              height: trackHeight,
              padding: const EdgeInsets.all(_inset),
              decoration: BoxDecoration(
                color: value ? themeState.primary : themeState.bgActive,
                borderRadius: BorderRadius.circular(K.radiusPill),
              ),
              child: AnimatedAlign(
                duration: AppMotion.state,
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    // Off, the thumb is a grey pebble rather than a white one:
                    // white on the dim track reads as a second "on" state.
                    color: value ? Colors.white : themeState.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
