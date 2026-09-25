import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../theme/theme_context.dart';

/// A line of text that becomes a field when you click it.
///
/// For the settings that are one short string and have no form around them —
/// a region's name, a region's address — where a label, a box and a Save
/// button would be three controls for a value you are only ever correcting.
///
/// Enter commits, Escape abandons, and leaving the field commits. The abandon
/// is safe because dropping the field also drops focus: the listener only
/// saves while still editing, and Escape stops editing first.
///
/// The whole width is the target rather than the glyphs, the same rule the
/// composer and the search pill follow — a name is a small thing to hit, and
/// the row around it is not.
class InlineEditText extends StatefulWidget {
  /// What to show when not editing. May differ from [value] — a region shows
  /// "Frankfurt (default)" and edits "Frankfurt".
  final String display;

  /// What the field starts with, and what a commit is compared against.
  final String value;

  final TextStyle style;

  /// Shown while the field is empty.
  final String hint;

  /// Refused rather than committed, so a bad value never reaches the server
  /// to come back as an error about a constraint. Null means it is fine.
  final String? Function(String)? validate;

  final int maxLength;
  final bool enabled;

  /// Called with the trimmed value, only when it is valid and different.
  final ValueChanged<String> onCommit;

  /// Told about a refusal, so the row can say why.
  final ValueChanged<String>? onInvalid;

  const InlineEditText({
    super.key,
    required this.display,
    required this.value,
    required this.style,
    required this.hint,
    required this.onCommit,
    this.validate,
    this.onInvalid,
    this.maxLength = 120,
    this.enabled = true,
  });

  @override
  State<InlineEditText> createState() => _InlineEditTextState();
}

class _InlineEditTextState extends State<InlineEditText> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    if (!widget.enabled) return;
    setState(() {
      _editing = true;
      _controller.text = widget.value;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
    _focus.requestFocus();
  }

  void _cancel() => setState(() => _editing = false);

  void _commit() {
    final next = _controller.text.trim();
    setState(() => _editing = false);
    if (next.isEmpty || next == widget.value) return;

    final refusal = widget.validate?.call(next);
    if (refusal != null) {
      widget.onInvalid?.call(refusal);
      return;
    }
    widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: _start,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: double.infinity,
            child: Text(
              widget.display,
              style: widget.style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    final theme = context.theme;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        style: widget.style,
        cursorColor: theme.textPrimary,
        onSubmitted: (_) => _commit(),
        inputFormatters: [LengthLimitingTextInputFormatter(widget.maxLength)],
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          hintText: widget.hint,
          hintStyle: widget.style.copyWith(color: theme.textQuaternary),
        ),
      ),
    );
  }
}
