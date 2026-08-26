import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/attachment_staging.dart';
import '../../../../logic/services/bot_command.dart';
import '../../../../logic/services/voice_note_recorder.dart';
import '../../../theme/app_motion.dart';
import '../../emoji_text.dart';
import '../../tap_to_focus.dart';
import 'composer_command_menu.dart';
import 'composer_input_row.dart';
import 'composer_plaintext_notice.dart';
import 'composer_recording_bar.dart';
import 'composer_staged_row.dart';

/// Message input row: attach + emoji buttons, the text field, a mic and the
/// send button, with a strip of staged-attachment chips above it once files
/// are picked. The emoji button opens a popover picker.
///
/// Enter sends, Shift+Enter inserts a newline (desktop convention). A message
/// with neither text nor attachments never sends. [footer] is an optional slot
/// below the bar — central DMs put the quota meter there.
part 'chat_composer_attachments.dart';
part 'chat_composer_recording.dart';

class ChatComposer extends StatefulWidget {
  /// Called with the trimmed text and any staged attachments.
  final void Function(String text, List<PendingAttachment> attachments) onSend;

  /// The bots on this server, for the `/` menu and the unencrypted warning.
  ///
  /// Empty everywhere bots cannot be addressed — DMs, central — which is also
  /// what turns both off: no bots, no `/` handling, and a slash is just a
  /// slash.
  final List<ServerMember> bots;

  /// Called (throttled by the caller) as the user types, to broadcast a typing
  /// indicator to the other members. Fires only for non-empty edits.
  final VoidCallback? onTyping;
  final String hintText;
  final bool enabled;
  final Widget? footer;

  /// Per-file size cap for this surface, in bytes.
  ///
  /// Checked here so an oversized file is refused with a sentence at the
  /// moment it is picked, rather than after it has been read, encrypted and
  /// pushed at a bucket that answers 413. The bucket's own `file_size_limit`
  /// is still the enforcement — this is the courtesy.
  final int maxAttachmentBytes;

  const ChatComposer({
    super.key,
    required this.onSend,
    this.onTyping,
    this.hintText = 'Send a message',
    this.enabled = true,
    this.footer,
    this.maxAttachmentBytes = ServerLimits.defaultMaxAttachmentBytes,
    this.bots = const [],
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with _ComposerAttachmentsMixin, _ComposerRecordingMixin {
  // Colours emoji as they are typed, matching how they render once sent.
  final TextEditingController _controller = EmojiTextEditingController();
  final FocusNode _focusNode = FocusNode();
  @override
  final List<PendingAttachment> _staged = [];

  @override
  bool get _atAttachmentLimit =>
      _staged.length >= AttachmentStaging.maxPerMessage;

  /// The bot this line will be sent to, or null when it is an ordinary
  /// message. Recomputed on each build from the text — one source of truth, so
  /// the warning above the bar and what actually gets sent cannot disagree.
  ///
  /// Attachments are excluded: a command carries no files (its body is the
  /// line, in the clear), and a staged file silently turning a command back
  /// into an ordinary message would be the worst kind of surprise.
  BotCommand? get _command => _staged.isNotEmpty
      ? null
      : BotCommands.parse(_controller.text, widget.bots);

  /// Replace the typed fragment with the chosen command and leave the caret
  /// after it, ready for arguments.
  void _pickCommand(String name) {
    _controller.text = '/$name ';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _focusNode.requestFocus();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // The bar lights its border while the field has focus.
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposeRecording();
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
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

  void _onTextChanged(String value) {
    // Rebuild so the send button enables/disables.
    setState(() {});
    if (value.trim().isNotEmpty) widget.onTyping?.call();
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grown into rather than snapped in. The strip appears above the
              // bar, so attaching the first file used to shove the whole
              // conversation up by the height of a row of chips, and removing
              // the last one dropped it back.
              AnimatedSize(
                duration: AppMotion.state,
                curve: AppMotion.settle,
                alignment: Alignment.bottomLeft,
                child: _staged.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : ComposerStagedRow(
                        staged: _staged,
                        themeState: themeState,
                        onRemove: _removeStaged,
                      ),
              ),
              // Above the bar, because the point of it is to be read *before*
              // the message goes.
              if (_command != null)
                ComposerPlaintextNotice(
                  bot: _command!.bot,
                  themeState: themeState,
                ),
              if (_suggestions.isNotEmpty)
                ComposerCommandMenu(
                  entries: _suggestions,
                  themeState: themeState,
                  onSelected: (_, name) => _pickCommand(name),
                ),
              _buildBar(themeState),
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

  /// What the `/` menu should be offering, or empty when it should be closed.
  List<({ServerMember bot, String name, String? description})>
  get _suggestions => (!widget.enabled || _isRecording)
      ? const []
      : BotCommands.suggest(_controller.text, widget.bots);

  /// The bar itself — one container whose height never changes between the
  /// input row and the recording row.
  ///
  /// The whole bar focuses the field, not only the line of text in the middle
  /// of it. The field is one line tall inside a 34px control row inside 6px of
  /// padding, so aiming at the bar and missing was the normal outcome — see
  /// [TapToFocus]. Not while recording: there is no field on the bar then.
  Widget _buildBar(ThemeState themeState) {
    return TapToFocus(
      focusNode: _focusNode,
      enabled: widget.enabled && !_isRecording,
      child: _buildBarBox(themeState),
    );
  }

  Widget _buildBarBox(ThemeState themeState) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: themeState.bgTertiary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          // Focus is carried by the accent ring rather than a caret alone —
          // the composer is the one place the whole bar should answer.
          color: _focusNode.hasFocus
              ? themeState.primary.withValues(alpha: 0.55)
              : themeState.borderElevated,
        ),
      ),
      child: _isRecording
          ? ComposerRecordingBar(
              elapsed: _elapsed,
              themeState: themeState,
              onCancel: _cancelRecording,
              onStop: _stopRecording,
            )
          : ComposerInputRow(
              controller: _controller,
              focusNode: _focusNode,
              themeState: themeState,
              enabled: widget.enabled,
              canSend:
                  widget.enabled &&
                  (_controller.text.trim().isNotEmpty || _staged.isNotEmpty),
              atAttachmentLimit: _atAttachmentLimit,
              hintText: widget.hintText,
              onChanged: _onTextChanged,
              onSubmit: _send,
              onPickFiles: _pickFiles,
              onStartRecording: _startRecording,
              onEmojiInserted: () => setState(() {}),
            ),
    );
  }
}
