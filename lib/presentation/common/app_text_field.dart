import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';
import 'tap_to_focus.dart';

/// Themed text field used throughout the app.
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool obscureText;
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
  /// Kept whether or not it is used, so a caller that starts passing its own
  /// node — or stops — doesn't leave this field wired to a dead one.
  final FocusNode _own = FocusNode();

  FocusNode get _node => widget.focusNode ?? _own;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.read<ThemeCubit>().state;
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
          obscureText: widget.obscureText,
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
          style: AppText.input.copyWith(color: themeState.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
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
