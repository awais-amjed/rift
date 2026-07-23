import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';

/// Message input row: multiline text field + send button.
///
/// Enter sends, Shift+Enter inserts a newline (desktop convention). Empty and
/// whitespace-only input never sends. [footer] is an optional slot below the
/// field — central DMs put the quota meter there.
class ChatComposer extends StatefulWidget {
  final ValueChanged<String> onSend;

  /// Called (throttled by the caller) as the user types, to broadcast a typing
  /// indicator to the other members. Fires only for non-empty edits.
  final VoidCallback? onTyping;
  final String hintText;
  final bool enabled;
  final Widget? footer;

  const ChatComposer({
    super.key,
    required this.onSend,
    this.onTyping,
    this.hintText = 'Send a message',
    this.enabled = true,
    this.footer,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _controller.clear();
    widget.onSend(text);
    _focusNode.requestFocus();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // Shift+Enter falls through to the TextField as a newline.
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: themeState.bgTertiary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: themeState.borderPrimary),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Focus(
                        onKeyEvent: _onKeyEvent,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: widget.enabled,
                          onChanged: (value) {
                            if (value.trim().isNotEmpty) widget.onTyping?.call();
                          },
                          minLines: 1,
                          maxLines: 6,
                          style: TextStyle(
                            fontSize: 14,
                            color: themeState.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: themeState.textQuaternary,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 5),
                      child: IconButton(
                        onPressed: widget.enabled ? _send : null,
                        icon: Icon(
                          Icons.send_rounded,
                          size: 19,
                          color: widget.enabled
                              ? themeState.primary
                              : themeState.textQuaternary,
                        ),
                        tooltip: 'Send',
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.footer != null) ...[
                const SizedBox(height: 6),
                widget.footer!,
              ],
            ],
          ),
        );
      },
    );
  }
}
