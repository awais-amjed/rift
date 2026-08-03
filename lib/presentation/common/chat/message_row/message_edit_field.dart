import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';

/// Inline editor that replaces a message's text while it is being edited —
/// Discord-style, rather than lifting the message into a dialog.
///
/// Enter saves, Shift+Enter adds a newline, Escape cancels; the same keys the
/// composer uses, so editing feels like writing.
class MessageEditField extends StatefulWidget {
  final String initialText;
  final ThemeState themeState;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;

  const MessageEditField({
    super.key,
    required this.initialText,
    required this.themeState,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<MessageEditField> createState() => _MessageEditFieldState();
}

class _MessageEditFieldState extends State<MessageEditField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  )..selection = TextSelection.collapsed(offset: widget.initialText.length);
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    // An empty edit would silently delete the message; make the user use
    // Delete for that instead.
    if (text.isEmpty) {
      widget.onCancel();
      return;
    }
    widget.onSave(text);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (isEnter && !HardwareKeyboard.instance.isShiftPressed) {
      _save();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeState;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          onKeyEvent: _onKey,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: null,
            style: TextStyle(fontSize: 14, color: theme.textSecondary),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: theme.bgTertiary,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.borderPrimary),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.borderPrimary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.primary, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'escape to cancel • enter to save',
          style: TextStyle(fontSize: 11, color: theme.textQuaternary),
        ),
      ],
    );
  }
}
