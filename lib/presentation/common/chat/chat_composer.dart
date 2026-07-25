import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/attachment.dart';
import '../../../data/classes/pending_attachment.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../../logic/helper_methods.dart';
import '../../../logic/services/mime_util.dart';

/// Message input row: attach button + multiline text field + send button, with
/// a row of staged-attachment chips above the field once files are picked.
///
/// Enter sends, Shift+Enter inserts a newline (desktop convention). A message
/// with neither text nor attachments never sends. [footer] is an optional slot
/// below the field — central DMs put the quota meter there.
class ChatComposer extends StatefulWidget {
  /// Called with the trimmed text and any staged attachments.
  final void Function(String text, List<PendingAttachment> attachments) onSend;

  /// Called (throttled by the caller) as the user types, to broadcast a typing
  /// indicator to the other members. Fires only for non-empty edits.
  final VoidCallback? onTyping;
  final String hintText;
  final bool enabled;
  final Widget? footer;

  /// Hard cap on how many files can ride on one message (bounds central-DM
  /// quota gaming and keeps a row readable).
  static const int maxAttachments = 10;

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
  final List<PendingAttachment> _staged = [];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (!widget.enabled) return;
    if (text.isEmpty && _staged.isEmpty) return;
    final attachments = List<PendingAttachment>.from(_staged);
    _controller.clear();
    setState(_staged.clear);
    widget.onSend(text, attachments);
    _focusNode.requestFocus();
  }

  Future<void> _pickFiles() async {
    if (!widget.enabled) return;
    try {
      final files = await openFiles();
      if (files.isEmpty) return;
      for (final file in files) {
        if (_staged.length >= ChatComposer.maxAttachments) {
          HelperMethods.showError(
            error: 'Up to ${ChatComposer.maxAttachments} files per message.',
          );
          break;
        }
        final bytes = await file.readAsBytes();
        final name = file.name;
        final mime = (file.mimeType != null && file.mimeType!.isNotEmpty)
            ? file.mimeType!
            : mimeFromName(name);
        _staged.add(PendingAttachment(
          bytes: bytes,
          name: name,
          mime: mime,
          kind: AttachmentKind.fromMime(mime),
        ));
      }
      if (mounted) setState(() {});
    } catch (e) {
      HelperMethods.printDebug('[Composer] file pick failed: $e');
      HelperMethods.showError(error: "Couldn't attach that file.");
    }
  }

  void _removeStaged(int index) {
    setState(() => _staged.removeAt(index));
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
        final canSend = widget.enabled &&
            (_controller.text.trim().isNotEmpty || _staged.isNotEmpty);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_staged.isNotEmpty)
                _StagedRow(
                  staged: _staged,
                  themeState: themeState,
                  onRemove: _removeStaged,
                ),
              Container(
                decoration: BoxDecoration(
                  color: themeState.bgTertiary,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: themeState.borderPrimary),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 5),
                      child: IconButton(
                        onPressed: widget.enabled ? _pickFiles : null,
                        icon: Icon(
                          Icons.add_circle_outline_rounded,
                          size: 20,
                          color: widget.enabled
                              ? themeState.textTertiary
                              : themeState.textQuaternary,
                        ),
                        tooltip: 'Attach files',
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    Expanded(
                      child: Focus(
                        onKeyEvent: _onKeyEvent,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: widget.enabled,
                          onChanged: (value) {
                            // Rebuild so the send button enables/disables.
                            setState(() {});
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
                              horizontal: 6,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 5),
                      child: IconButton(
                        onPressed: canSend ? _send : null,
                        icon: Icon(
                          Icons.send_rounded,
                          size: 19,
                          color: canSend
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

/// The horizontal strip of staged-attachment chips shown above the input.
class _StagedRow extends StatelessWidget {
  final List<PendingAttachment> staged;
  final ThemeState themeState;
  final ValueChanged<int> onRemove;

  const _StagedRow({
    required this.staged,
    required this.themeState,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: staged.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _StagedChip(
          attachment: staged[i],
          themeState: themeState,
          onRemove: () => onRemove(i),
        ),
      ),
    );
  }
}

class _StagedChip extends StatelessWidget {
  final PendingAttachment attachment;
  final ThemeState themeState;
  final VoidCallback onRemove;

  const _StagedChip({
    required this.attachment,
    required this.themeState,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.kind == AttachmentKind.image;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: isImage ? 76 : 150,
          height: 76,
          decoration: BoxDecoration(
            color: themeState.bgSecondary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: themeState.borderPrimary),
          ),
          clipBehavior: Clip.antiAlias,
          child: isImage
              ? Image.memory(attachment.bytes, fit: BoxFit.cover)
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Icon(
                        attachment.kind == AttachmentKind.audio
                            ? Icons.audiotrack_rounded
                            : Icons.insert_drive_file_outlined,
                        size: 20,
                        color: themeState.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          attachment.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: themeState.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: BoxDecoration(
                color: themeState.bgPrimary,
                shape: BoxShape.circle,
                border: Border.all(color: themeState.borderPrimary),
              ),
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: themeState.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}
