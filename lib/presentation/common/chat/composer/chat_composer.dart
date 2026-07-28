import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/classes/pending_attachment.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/mime_util.dart';
import '../../../../logic/services/voice_note_recorder.dart';
import 'composer_emoji_panel.dart';
import 'composer_icon_button.dart';
import 'composer_recording_bar.dart';
import 'composer_send_button.dart';
import 'composer_staged_row.dart';
import 'composer_text_field.dart';

/// Message input row: attach + emoji buttons, the text field, a mic and the
/// send button, with a strip of staged-attachment chips above it once files
/// are picked and an emoji panel below it on demand.
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

  final VoiceNoteRecorder _recorder = VoiceNoteRecorder();
  bool _isRecording = false;
  Duration _elapsed = Duration.zero;
  Timer? _recordTimer;

  bool _showEmoji = false;

  bool get _atAttachmentLimit => _staged.length >= ChatComposer.maxAttachments;

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
        if (_atAttachmentLimit) {
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
        _staged.add(
          PendingAttachment(
            bytes: bytes,
            name: name,
            mime: mime,
            kind: AttachmentKind.fromMime(mime),
          ),
        );
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

  void _toggleEmoji() {
    setState(() => _showEmoji = !_showEmoji);
    // Keep the field focused so inserted emoji land at the cursor.
    if (_showEmoji) _focusNode.requestFocus();
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
              if (_showEmoji && !_isRecording)
                ComposerEmojiPanel(
                  controller: _controller,
                  themeState: themeState,
                  onEmojiSelected: () => setState(() {}),
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: themeState.bgTertiary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _focusNode.hasFocus
              ? themeState.primary.withValues(alpha: 0.55)
              : themeState.borderPrimary,
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
      children: [
        ComposerIconButton(
          icon: Icons.attach_file_rounded,
          tooltip: 'Attach files',
          themeState: themeState,
          onPressed: widget.enabled ? _pickFiles : null,
        ),
        ComposerIconButton(
          icon: Icons.sentiment_satisfied_alt_rounded,
          tooltip: 'Emoji',
          themeState: themeState,
          active: _showEmoji,
          onPressed: widget.enabled ? _toggleEmoji : null,
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
