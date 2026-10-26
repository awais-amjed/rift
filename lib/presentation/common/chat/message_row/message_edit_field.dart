import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/constants.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../context_menu/text_field_context_menu.dart';

/// Inline editor that replaces a message's text while it is being edited —
/// Discord-style, rather than lifting the message into a dialog.
///
/// Enter saves, Shift+Enter adds a newline, Escape cancels; the same keys the
/// composer uses, so editing feels like writing. The words under the field
/// do the same when clicked: with only the keys, a mouse or a phone had no
/// way out of an edit.
class MessageEditField extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;

  const MessageEditField({
    super.key,
    required this.initialText,
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
    final theme = context.theme;
    final hint = AppText.label.copyWith(
      fontWeight: FontWeight.w400,
      color: theme.textTertiary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          onKeyEvent: _onKey,
          child: TextField(
            contextMenuBuilder: TextFieldContextMenu.builder,
            controller: _controller,
            focusNode: _focusNode,
            maxLines: null,
            style: AppText.body.copyWith(color: theme.textSecondary),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: theme.bgTertiary,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(K.radiusRow),
                borderSide: BorderSide(color: theme.borderPrimary),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(K.radiusRow),
                borderSide: BorderSide(color: theme.borderPrimary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(K.radiusRow),
                borderSide: BorderSide(color: theme.primary, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: context.layoutMode.isCompact
              ? [
                  _HintAction(label: 'cancel', onTap: widget.onCancel),
                  Text(' • ', style: hint),
                  _HintAction(label: 'save', onTap: _save),
                ]
              : [
                  Text('escape to ', style: hint),
                  _HintAction(label: 'cancel', onTap: widget.onCancel),
                  Text(' • enter to ', style: hint),
                  _HintAction(label: 'save', onTap: _save),
                ],
        ),
      ],
    );
  }
}

/// One of the hint's words that also does what it names.
class _HintAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _HintAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: onTap,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(
          label,
          style: AppText.label.copyWith(color: context.theme.primary),
        ),
      ),
    ),
  );
}
