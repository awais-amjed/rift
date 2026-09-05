import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

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
  final bool enabled;
  final String hintText;
  final ValueChanged<String> onChanged;

  /// Enter sends; Shift+Enter falls through to the field as a newline.
  final VoidCallback onSubmit;

  const ComposerTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hintText,
    required this.onChanged,
    required this.onSubmit,
  });

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
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
    );
  }
}
