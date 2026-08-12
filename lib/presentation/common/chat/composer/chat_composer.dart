import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/attachment_staging.dart';
import '../../../../logic/services/voice_note_recorder.dart';
import '../../emoji_text.dart';
import 'composer_icon_button.dart';
import 'composer_recording_bar.dart';
import 'composer_send_button.dart';
import 'composer_staged_row.dart';
import 'composer_text_field.dart';
import 'emoji_picker_popup.dart';

/// Message input row: attach + emoji buttons, the text field, a mic and the
/// send button, with a strip of staged-attachment chips above it once files
/// are picked. The emoji button opens a popover picker.
///
/// Enter sends, Shift+Enter inserts a newline (desktop convention). A message
/// with neither text nor attachments never sends. [footer] is an optional slot
/// below the bar — central DMs put the quota meter there.
class ChatComposer extends StatefulWidget {
  /// Called with the trimmed text and any staged attachments.
  final void Function(String text, List<PendingAttachment> attachments) onSend;

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
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  // Colours emoji as they are typed, matching how they render once sent.
  final TextEditingController _controller = EmojiTextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<PendingAttachment> _staged = [];

  final VoiceNoteRecorder _recorder = VoiceNoteRecorder();
  bool _isRecording = false;
  Duration _elapsed = Duration.zero;
  Timer? _recordTimer;

  bool get _atAttachmentLimit =>
      _staged.length >= AttachmentStaging.maxPerMessage;

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
    _recordTimer?.cancel();
    _recorder.dispose();
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

  Future<void> _pickFiles() async {
    if (!widget.enabled) return;
    try {
      final files = await openFiles();
      if (files.isEmpty) return;
      for (final file in files) {
        final bytes = await file.readAsBytes();
        // One rejected file doesn't abandon the rest of the selection.
        if (!_accepts(name: file.name, bytes: bytes.length)) continue;
        _staged.add(
          await AttachmentStaging.stage(
            bytes: bytes,
            name: file.name,
            mimeType: file.mimeType,
          ),
        );
      }
      if (mounted) setState(() {});
    } catch (e) {
      HelperMethods.printDebug('[Composer] file pick failed: $e');
      HelperMethods.showError(error: "Couldn't attach that file.");
    }
  }

  /// True when the file fits; shows the reason and returns false when it
  /// doesn't.
  bool _accepts({required String name, required int bytes}) {
    final rejection = AttachmentStaging.rejectionFor(
      name: name,
      bytes: bytes,
      maxBytes: widget.maxAttachmentBytes,
      alreadyStaged: _staged.length,
    );
    if (rejection == null) return true;
    HelperMethods.showError(error: rejection);
    return false;
  }

  void _removeStaged(int index) {
    setState(() => _staged.removeAt(index));
  }

  Future<void> _openEmojiPicker(BuildContext anchorContext) async {
    // Keep the field focused so inserted emoji land at the cursor.
    _focusNode.requestFocus();
    await showEmojiPickerPopup(
      anchorContext,
      controller: _controller,
      onEmojiSelected: () => setState(() {}),
    );
  }

  // ── Voice notes ───────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!widget.enabled || _isRecording || _atAttachmentLimit) return;
    try {
      if (!await _recorder.hasPermission()) {
        HelperMethods.showError(error: 'Microphone permission denied.');
        return;
      }
      await _recorder.start();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _elapsed = Duration.zero;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
      });
    } catch (e) {
      HelperMethods.printDebug('[Composer] record start failed: $e');
      HelperMethods.showError(
        error: "Couldn't start recording — is a microphone available?",
      );
    }
  }

  /// Stop and stage the recording as an audio attachment.
  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final durationMs = _elapsed.inMilliseconds;
    try {
      final bytes = await _recorder.stop();
      if (!mounted) return;
      // A long enough recording outgrows the cap the same way a picked file
      // does, and finding that out at upload time would lose the take.
      if (bytes != null &&
          !_accepts(name: 'That recording', bytes: bytes.length)) {
        setState(() => _isRecording = false);
        return;
      }
      setState(() {
        _isRecording = false;
        if (bytes != null) {
          _staged.add(
            PendingAttachment(
              bytes: bytes,
              name: 'Voice message.m4a',
              mime: 'audio/mp4',
              kind: AttachmentKind.audio,
              durationMs: durationMs,
            ),
          );
        }
      });
    } catch (e) {
      HelperMethods.printDebug('[Composer] reading recording failed: $e');
      if (mounted) setState(() => _isRecording = false);
      HelperMethods.showError(error: "Couldn't save the recording.");
    }
  }

  /// Discard the in-progress recording.
  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _recorder.cancel();
    if (mounted) setState(() => _isRecording = false);
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
              if (_staged.isNotEmpty)
                ComposerStagedRow(
                  staged: _staged,
                  themeState: themeState,
                  onRemove: _removeStaged,
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

  /// The bar itself — one container whose height never changes between the
  /// input row and the recording row.
  Widget _buildBar(ThemeState themeState) {
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
          : _buildInputRow(themeState),
    );
  }

  Widget _buildInputRow(ThemeState themeState) {
    final canSend =
        widget.enabled &&
        (_controller.text.trim().isNotEmpty || _staged.isNotEmpty);
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
          onPressed: widget.enabled ? _pickFiles : null,
        ),
        Expanded(
          child: ComposerTextField(
            controller: _controller,
            focusNode: _focusNode,
            themeState: themeState,
            enabled: widget.enabled,
            hintText: widget.hintText,
            onChanged: _onTextChanged,
            onSubmit: _send,
          ),
        ),
        // Builder so the popover can anchor to the button's own box.
        Builder(
          builder: (buttonContext) => ComposerIconButton(
            icon: Icons.sentiment_satisfied_alt_rounded,
            tooltip: 'Emoji',
            themeState: themeState,
            onPressed: widget.enabled
                ? () => _openEmojiPicker(buttonContext)
                : null,
          ),
        ),
        ComposerIconButton(
          icon: Icons.mic_none_rounded,
          tooltip: 'Record a voice message',
          themeState: themeState,
          onPressed: (widget.enabled && !_atAttachmentLimit)
              ? _startRecording
              : null,
        ),
        ComposerSendButton(
          themeState: themeState,
          enabled: canSend,
          onPressed: _send,
        ),
      ],
    );
  }
}
