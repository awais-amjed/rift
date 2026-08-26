import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
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
  final ThemeState themeState;
  final bool enabled;
  final bool canSend;
  final bool atAttachmentLimit;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onPickFiles;
  final VoidCallback onStartRecording;
  final VoidCallback onEmojiInserted;

  const ComposerInputRow({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.themeState,
    required this.enabled,
    required this.canSend,
    required this.atAttachmentLimit,
    required this.hintText,
    required this.onChanged,
    required this.onSubmit,
    required this.onPickFiles,
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
        ComposerIconButton(
          icon: Icons.add_rounded,
          tooltip: 'Attach files',
          themeState: themeState,
          onPressed: enabled ? onPickFiles : null,
        ),
        Expanded(
          child: ComposerTextField(
            controller: controller,
            focusNode: focusNode,
            themeState: themeState,
            enabled: enabled,
            hintText: hintText,
            onChanged: onChanged,
            onSubmit: onSubmit,
          ),
        ),
        // Builder so the popover can anchor to the button's own box.
        Builder(
          builder: (buttonContext) => ComposerIconButton(
            icon: Icons.sentiment_satisfied_alt_rounded,
            tooltip: 'Emoji',
            themeState: themeState,
            onPressed: enabled ? () => _openEmojiPicker(buttonContext) : null,
          ),
        ),
        ComposerIconButton(
          icon: Icons.mic_none_rounded,
          tooltip: 'Record a voice message',
          themeState: themeState,
          onPressed: (enabled && !atAttachmentLimit) ? onStartRecording : null,
        ),
        ComposerSendButton(
          themeState: themeState,
          enabled: canSend,
          onPressed: onSubmit,
        ),
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
