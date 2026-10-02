import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../responsive/shell_scope.dart';
import '../theme/app_motion.dart';
import '../theme/theme_context.dart';

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
class AppSwitch extends StatefulWidget {
  final bool value;

  /// Null renders the toggle locked — the caller dims it.
  final ValueChanged<bool>? onChanged;

  const AppSwitch({super.key, required this.value, required this.onChanged});

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

/// Holds whether to draw the focus ring. Keyboard-reachable because a
/// GestureDetector alone is not: Tab skipped every switch in the app, so a
/// form like "Create channel" had a setting you could not reach without a
/// mouse.
class _AppSwitchState extends State<AppSwitch> {
  static const double _trackWidth = 38;
  static const double _trackHeight = 22;
  static const double _thumbSize = 18;
  static const double _inset = 2;

  static const double _touchTrackWidth = 44;
  static const double _touchTrackHeight = 26;
  static const double _touchThumbSize = 22;

  /// Only while focus came by keyboard — [FocusableActionDetector] says when.
  bool _showFocus = false;

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  Widget build(BuildContext context) {
    final touch = context.layoutMode.isCompact;
    final trackWidth = touch ? _touchTrackWidth : _trackWidth;
    final trackHeight = touch ? _touchTrackHeight : _trackHeight;
    final thumbSize = touch ? _touchThumbSize : _thumbSize;
    final value = widget.value;
    final enabled = widget.onChanged != null;

    final themeState = context.theme;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (show) => setState(() => _showFocus = show),
      // Space and Enter, as on any other toggle.
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => _toggle(),
        ),
      },
      child: GestureDetector(
        onTap: enabled ? _toggle : null,
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
          // A foreground ring, so it takes no room from the thumb's travel.
          foregroundDecoration: _showFocus && enabled
              ? BoxDecoration(
                  border: Border.all(
                    color: themeState.textPrimary,
                    width: K.focusRingWidth,
                  ),
                  borderRadius: BorderRadius.circular(K.radiusPill),
                )
              : null,
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
                color: value ? themeState.onPrimary : themeState.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
