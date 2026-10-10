import 'package:flutter/material.dart';

import 'composer_add_button.dart';
import 'composer_command_backdrop.dart';
import 'composer_icon_button.dart';
import 'composer_send_button.dart';
import 'composer_text_field.dart';
import 'emoji_picker_popup.dart';

/// The row of controls inside the composer bar: attach, the text field, emoji,
/// mic, send.
///
/// A widget rather than a method on the composer's State, because it reads
/// nothing but what is passed to it — and because the bar it sits in has two
/// contents (this, and the recording bar) that should be two things.
class ComposerInputRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Passed straight to [ComposerTextField] — see its doc.
  final CommandShape? commandShape;
  final bool enabled;
  final bool canSend;
  final bool atAttachmentLimit;

  /// Whether this member's role lets them attach anything. False disables the
  /// two controls that make one — the picker and the voice note — and says so
  /// in their tooltip; an absent control explains nothing.
  final bool canAttach;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  /// Passed straight to [ComposerTextField] — see its doc.
  final bool Function({bool sending})? onAcceptSuggestion;
  final VoidCallback onPickFiles;

  /// Start a poll, offered from the "+" beside attaching. Null where there
  /// are no polls.
  final VoidCallback? onCreatePoll;
  final VoidCallback onStartRecording;
  final VoidCallback onEmojiInserted;

  const ComposerInputRow({
    super.key,
    required this.controller,
    required this.focusNode,
    this.commandShape,
    required this.enabled,
    required this.canSend,
    required this.atAttachmentLimit,
    this.canAttach = true,
    required this.hintText,
    required this.onChanged,
    required this.onSubmit,
    this.onAcceptSuggestion,
    required this.onPickFiles,
    this.onCreatePoll,
    required this.onStartRecording,
    required this.onEmojiInserted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      // A hair apart, so the controls read as a row of separate targets
      // rather than one welded strip.
      spacing: 2,
      children: [
        // A plus rather than a paperclip: it opens the one "add something"
        // affordance on the bar, and it is the only control left of the text.
        ComposerAddButton(
          enabled: enabled,
          canAttach: canAttach,
          onPickFiles: onPickFiles,
          onCreatePoll: onCreatePoll,
        ),
        Expanded(
          child: ComposerTextField(
            controller: controller,
            focusNode: focusNode,
            commandShape: commandShape,
            enabled: enabled,
            hintText: hintText,
            onChanged: onChanged,
            onSubmit: onSubmit,
            onAcceptSuggestion: onAcceptSuggestion,
          ),
        ),
        // Builder so the popover can anchor to the button's own box.
        Builder(
          builder: (buttonContext) => ComposerIconButton(
            icon: Icons.sentiment_satisfied_alt_rounded,
            tooltip: 'Emoji',

            onPressed: enabled ? () => _openEmojiPicker(buttonContext) : null,
          ),
        ),
        ComposerIconButton(
          icon: Icons.mic_none_rounded,
          // A voice note is an attachment, and is refused by the same policy.
          tooltip: canAttach
              ? 'Record a voice message'
              : 'Your role cannot attach files here',

          onPressed: (enabled && canAttach && !atAttachmentLimit)
              ? onStartRecording
              : null,
        ),
        ComposerSendButton(enabled: canSend, onPressed: onSubmit),
      ],
    );
  }

  Future<void> _openEmojiPicker(BuildContext anchorContext) async {
    // Keep the field focused so inserted emoji land at the cursor.
    focusNode.requestFocus();
    await showEmojiPickerPopup(
      anchorContext,
      controller: controller,
      onEmojiSelected: onEmojiInserted,
    );
  }
}
