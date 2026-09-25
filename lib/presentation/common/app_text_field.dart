import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/constants.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import 'tap_to_focus.dart';

/// Over the widget budget and one job: the app's text field and its label,
/// counter and reveal button.
///
/// Themed text field used throughout the app.
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? label;
  final String? hint;

  /// A secret. It comes with a button to show what was typed — see
  /// [canReveal].
  final bool obscureText;

  /// Whether an [obscureText] field offers to show its contents.
  ///
  /// On by default. A password you cannot see is one you cannot check, and a
  /// second "confirm" field only asks for the same invisible typo twice — so
  /// the app checks a secret by letting you read it instead. Off only where
  /// showing it would defeat the field.
  final bool canReveal;
  final bool enabled;
  final TextInputType? keyboardType;

  /// Restricts what can be typed, e.g. digits only for a numeric limit.
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;

  /// Called when the field is submitted — Enter on a desktop, the keyboard's
  /// action key on a phone. For a field whose whole content is one value that
  /// a button then acts on, this is the same decision as pressing the button.
  final ValueChanged<String>? onSubmitted;

  /// Passed in when something outside has to focus the field — a page that
  /// seeds it, a form that moves between fields. Left null the field manages
  /// its own.
  final FocusNode? focusNode;

  final bool autofocus;

  /// More than one turns the field into a box that grows to this many lines
  /// and then scrolls — for prose (a server description), not for a value.
  final int maxLines;

  /// Caps the text and shows the remaining count. Set it where a database
  /// column has a limit, so the field refuses the 301st character rather than
  /// the save doing it.
  final int? maxLength;

  const AppTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.obscureText = false,
    this.canReveal = true,
    this.enabled = true,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  /// The size the line box and the padding are worked out from.
  static final double _fontSize = AppText.input.fontSize!;

  /// Kept whether or not it is used, so a caller that starts passing its own
  /// node — or stops — doesn't leave this field wired to a dead one.
  final FocusNode _own = FocusNode();

  FocusNode get _node => widget.focusNode ?? _own;

  /// Whether a secret is currently shown in the clear. Always starts hidden.
  bool _revealed = false;

  bool get _obscured => widget.obscureText && !_revealed;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final borderColor = themeState.borderElevated;
    // A focused field is ringed in a *tinted* accent, not the flat accent —
    // full strength reads as an error state next to the quiet surfaces around
    // it.
    final focusColor = themeState.primary.withValues(alpha: 0.55);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          // The label answers for the field, the way a web label does. It sits
          // seven pixels above a box people already aim at loosely, and a click
          // that lands on the word rather than under it should still put the
          // caret where the click was clearly meant to go.
          TapToFocus(
            focusNode: _node,
            enabled: widget.enabled,
            child: Text(
              widget.label!.toUpperCase(),
              style: AppText.sectionLabel.copyWith(
                color: themeState.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 7),
        ],
        TextField(
          controller: widget.controller,
          obscureText: _obscured,
          enabled: widget.enabled,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          onChanged: widget.onChanged,
          onEditingComplete: widget.onEditingComplete,
          onSubmitted: widget.onSubmitted,
          focusNode: _node,
          autofocus: widget.autofocus,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          style: AppText.input.copyWith(
            height: K.fieldLineHeight,
            color: themeState.textPrimary,
          ),
          // Pin the line box, as the composer does: a taller glyph (an emoji)
          // would otherwise stretch the line and the field with it.
          strutStyle: StrutStyle(
            fontSize: _fontSize,
            height: K.fieldLineHeight,
            forceStrutHeight: true,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            suffixIcon: widget.obscureText && widget.canReveal
                ? _RevealButton(
                    revealed: _revealed,
                    onPressed: () => setState(() => _revealed = !_revealed),
                  )
                : null,
            // The button sits inside the field's height rather than setting
            // it, so a revealable field is no taller than a plain one.
            suffixIconConstraints: const BoxConstraints.tightFor(
              width: K.iconButtonSize,
              height: K.iconButtonSize,
            ),
            hintStyle: AppText.input.copyWith(color: themeState.textQuaternary),
            filled: true,
            fillColor: themeState.bgTertiary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
              borderSide: BorderSide(color: focusColor, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
              borderSide: BorderSide(color: borderColor.withValues(alpha: 0.5)),
            ),
            // The shared control height, so a field and the button beside it
            // are one size: one pinned line plus this padding comes to exactly
            // [K.fieldHeight], and a prose box still grows with its lines.
            //
            // Padding rather than a `minHeight` constraint, which is what this
            // used to be. Material applies that to the field's *slot*, not to
            // the outline it paints, so the field took 44px and drew a 34px
            // box at the top of it — ten pixels shorter than the button beside
            // it, with a strip of nothing underneath.
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: (K.fieldHeight - _fontSize * K.fieldLineHeight) / 2,
            ),
            // Dense, or Material floors the box at its own 48 first.
            isDense: true,
            // And standard, for the reason [AppButton] gives: on a desktop the
            // adaptive default is compact, which takes another 8px off the box
            // and nothing else around it.
            visualDensity: VisualDensity.standard,
            // Material's counter is a second line of text under the field, in
            // the wrong colour and at the wrong weight. Keep the count — it is
            // the point of setting a limit — and dress it like every other
            // helper line in the app.
            counterStyle: AppText.secondary.copyWith(
              color: themeState.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The eye in a secret field's trailing edge.
class _RevealButton extends StatelessWidget {
  final bool revealed;
  final VoidCallback onPressed;

  const _RevealButton({required this.revealed, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return IconButton(
      tooltip: revealed ? 'Hide' : 'Show',
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      icon: Icon(
        revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 18,
        color: themeState.textTertiary,
      ),
    );
  }
}
