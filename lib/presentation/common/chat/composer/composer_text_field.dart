import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'composer_command_backdrop.dart';

/// The composer's text input, stripped of the global filled [InputDecoration]
/// so it reads as part of the bar rather than a box inside it.
///
/// The field shrink-wraps its text, is then floored to one control height and
/// centred there, so the text sits on the icons' centre line whatever the
/// font's metrics are — and still grows, downward, for multi-line input.
class ComposerTextField extends StatelessWidget {
  static const int _maxLines = 6;

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Where a bot command sits in the text, drawn apart from a message by
  /// [ComposerCommandBackdrop]; null for an ordinary message.
  final CommandShape? commandShape;
  final bool enabled;
  final String hintText;
  final ValueChanged<String> onChanged;

  /// Enter sends; Shift+Enter falls through to the field as a newline.
  final VoidCallback onSubmit;

  /// First refusal on Enter and Tab, for the `@` and `/` menus.
  ///
  /// An autocomplete that only takes a mouse click is a trap in a field you
  /// are typing into: with the menu open, Enter sent `@ben` as a message
  /// rather than completing it. Returns true when it consumed the key.
  /// [sending] is Enter, which declines a line that is already a whole
  /// command, so it sends.
  final bool Function({bool sending})? onAcceptSuggestion;

  /// Up (-1) and Down (+1), offered to whichever menu is open before the
  /// field moves its caret. Returns true when a menu took the key.
  final bool Function(int delta)? onMoveSuggestion;

  const ComposerTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.commandShape,
    required this.enabled,
    required this.hintText,
    required this.onChanged,
    required this.onSubmit,
    this.onAcceptSuggestion,
    this.onMoveSuggestion,
  });

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // Arrows repeat while held, and holding Down should run down the list.
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final delta = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowDown => 1,
        LogicalKeyboardKey.arrowUp => -1,
        _ => 0,
      };
      if (delta != 0 &&
          !HardwareKeyboard.instance.isShiftPressed &&
          (onMoveSuggestion?.call(delta) ?? false)) {
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Tab belongs to the menus alone: with nothing open it is still the way
    // out of the field.
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      return (onAcceptSuggestion?.call() ?? false)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    // A suggestion showing takes Enter first — otherwise the half-typed name
    // it is offering to complete goes out as the message.
    if (onAcceptSuggestion?.call(sending: true) ?? false) {
      return KeyEventResult.handled;
    }
    onSubmit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: K.composerControlSize),
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: K.composerFieldVPad),
          child: Focus(
            onKeyEvent: _onKeyEvent,
            child: ComposerCommandBackdrop(
              controller: controller,
              shape: commandShape,
              placeholderStyle: AppText.input.copyWith(
                height: K.composerLineHeight,
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                onChanged: onChanged,
                minLines: 1,
                maxLines: _maxLines,
                style: AppText.input.copyWith(
                  height: K.composerLineHeight,
                  color: themeState.textPrimary,
                ),
                // Pin the line box: without this an emoji (or any taller glyph)
                // stretches the line and the whole bar jumps as you type.
                strutStyle: StrutStyle(
                  fontSize: AppText.input.fontSize,
                  height: K.composerLineHeight,
                  forceStrutHeight: true,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  // One line, always. The field grows to `_maxLines` for what
                  // you type, and the hint inherits that room — so in a narrow
                  // conversation pane "Message Schema Tester" broke a word per
                  // line and pushed the whole bar taller before a key was
                  // pressed. The placeholder should shorten, not reflow.
                  hintMaxLines: 1,
                  // Same metrics as the real text, so the hint sits exactly
                  // where typing will start.
                  hintStyle: AppText.input.copyWith(
                    height: K.composerLineHeight,
                    color: themeState.textQuaternary,
                  ),
                  // The bar itself is the surface — don't paint the global
                  // filled InputDecoration box inside it.
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isCollapsed: true,
                  isDense: true,
                  // Vertical room comes from the Padding above; keep the
                  // decorator out of it so nothing biases the text off centre.
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
