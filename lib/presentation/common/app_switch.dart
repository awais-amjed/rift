import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';

/// The app's on/off toggle.
///
/// Hand-built rather than a restyled Material [Switch]: the design pins the
/// track at 38×22 around an 18px thumb, and Material's switch geometry is
/// fixed at half again that size with no way to bring it down.
class AppSwitch extends StatelessWidget {
  final bool value;

  /// Null renders the toggle locked — the caller dims it.
  final ValueChanged<bool>? onChanged;

  const AppSwitch({super.key, required this.value, required this.onChanged});

  static const double _trackWidth = 38;
  static const double _trackHeight = 22;
  static const double _thumbSize = 18;
  static const double _inset = 2;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return MouseRegion(
          cursor: onChanged == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              width: _trackWidth,
              height: _trackHeight,
              padding: const EdgeInsets.all(_inset),
              decoration: BoxDecoration(
                color: value ? themeState.primary : themeState.bgActive,
                borderRadius: BorderRadius.circular(K.radiusPill),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: _thumbSize,
                  height: _thumbSize,
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
