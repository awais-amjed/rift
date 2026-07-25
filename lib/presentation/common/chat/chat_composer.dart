import 'dart:async';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _elapsed = Duration.zero;
  Timer? _recordTimer;
  String? _recordPath;

  bool _showEmoji = false;

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
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
    if (!widget.enabled ||
        _isRecording ||
        _staged.length >= ChatComposer.maxAttachments) {
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        HelperMethods.showError(error: 'Microphone permission denied.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/rift_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: path,
      );
      if (!mounted) return;
      _recordPath = path;
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
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      HelperMethods.printDebug('[Composer] record stop failed: $e');
    }
    if (!mounted) return;
    setState(() => _isRecording = false);
    if (path == null) return;

    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      await file.delete().catchError((_) => file);
      if (!mounted) return;
      setState(() {
        _staged.add(
          PendingAttachment(
            bytes: bytes,
            name: 'Voice message.m4a',
            mime: 'audio/mp4',
            kind: AttachmentKind.audio,
            durationMs: durationMs,
          ),
        );
      });
    } catch (e) {
      HelperMethods.printDebug('[Composer] reading recording failed: $e');
      HelperMethods.showError(error: "Couldn't save the recording.");
    }
  }

  /// Discard the in-progress recording.
  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _recorder.cancel();
    } catch (_) {
      // ignore — nothing to keep anyway
    }
    final path = _recordPath;
    if (path != null) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
    if (mounted) setState(() => _isRecording = false);
  }

  String _fmtElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// The in-progress recording row. Returns a bare Row (the shared bar
  /// container wraps it) with the same 38px controls as the input row, so the
  /// bar keeps its height when recording starts.
  Widget _recordingBar(ThemeState themeState) {
    return Row(
      children: [
        _ComposerIconButton(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Discard',
          themeState: themeState,
          onPressed: _cancelRecording,
        ),
        const SizedBox(width: 2),
        Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: Color(0xFFE5484D),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          'Recording…',
          style: TextStyle(fontSize: 14, color: themeState.textSecondary),
        ),
        const Spacer(),
        Text(
          _fmtElapsed(_elapsed),
          style: TextStyle(
            fontSize: 13,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: themeState.textTertiary,
          ),
        ),
        const SizedBox(width: 4),
        _ComposerIconButton(
          icon: Icons.stop_circle_rounded,
          tooltip: 'Stop & attach',
          themeState: themeState,
          active: true,
          onPressed: _stopRecording,
        ),
      ],
    );
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
        final canSend =
            widget.enabled &&
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: BoxDecoration(
                  color: themeState.bgTertiary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: themeState.borderPrimary),
                ),
                child: _isRecording
                    ? _recordingBar(themeState)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _ComposerIconButton(
                            icon: Icons.add_rounded,
                            tooltip: 'Attach files',
                            themeState: themeState,
                            onPressed: widget.enabled ? _pickFiles : null,
                          ),
                          _ComposerIconButton(
                            icon: Icons.emoji_emotions_outlined,
                            tooltip: 'Emoji',
                            themeState: themeState,
                            active: _showEmoji,
                            onPressed: widget.enabled ? _toggleEmoji : null,
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
                                  if (value.trim().isNotEmpty) {
                                    widget.onTyping?.call();
                                  }
                                },
                                minLines: 1,
                                maxLines: 6,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: themeState.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText: widget.hintText,
                                  hintStyle: TextStyle(
                                    fontSize: 14,
                                    color: themeState.textQuaternary,
                                  ),
                                  // The bar itself is the surface — don't paint the
                                  // global filled InputDecoration box inside it.
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  isCollapsed: true,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _ComposerIconButton(
                            icon: Icons.mic_none_rounded,
                            tooltip: 'Record a voice message',
                            themeState: themeState,
                            onPressed:
                                (widget.enabled &&
                                    _staged.length <
                                        ChatComposer.maxAttachments)
                                ? _startRecording
                                : null,
                          ),
                          const SizedBox(width: 2),
                          _SendButton(
                            themeState: themeState,
                            enabled: canSend,
                            onPressed: _send,
                          ),
                        ],
                      ),
              ),
              if (widget.footer != null) ...[
                const SizedBox(height: 6),
                widget.footer!,
              ],
              if (_showEmoji && !_isRecording)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    height: 256,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: EmojiPicker(
                        textEditingController: _controller,
                        onEmojiSelected: (_, _) => setState(() {}),
                        config: Config(
                          height: 256,
                          emojiViewConfig: EmojiViewConfig(
                            backgroundColor: themeState.bgSecondary,
                            columns: 9,
                            emojiSizeMax: 26,
                          ),
                          categoryViewConfig: CategoryViewConfig(
                            backgroundColor: themeState.bgSecondary,
                            iconColor: themeState.textQuaternary,
                            iconColorSelected: themeState.primary,
                            indicatorColor: themeState.primary,
                            dividerColor: themeState.borderPrimary,
                            backspaceColor: themeState.primary,
                          ),
                          bottomActionBarConfig: const BottomActionBarConfig(
                            enabled: false,
                          ),
                          searchViewConfig: SearchViewConfig(
                            backgroundColor: themeState.bgSecondary,
                            buttonIconColor: themeState.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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
              child: Icon(
                Icons.close,
                size: 14,
                color: themeState.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A uniform, square tap-target icon for the composer's action row (attach,
/// emoji, mic). Fixed size so every control lines up regardless of the icon.
class _ComposerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final ThemeState themeState;
  final VoidCallback? onPressed;
  final bool active;

  const _ComposerIconButton({
    required this.icon,
    required this.tooltip,
    required this.themeState,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = active
        ? themeState.primary
        : (enabled ? themeState.textTertiary : themeState.textQuaternary);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        hoverColor: themeState.bgHover,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 21, color: color),
        ),
      ),
    );
  }
}

/// The send button: a filled accent circle when there's something to send,
/// a muted ghost icon otherwise. Same footprint as [_ComposerIconButton].
class _SendButton extends StatelessWidget {
  final ThemeState themeState;
  final bool enabled;
  final VoidCallback onPressed;

  const _SendButton({
    required this.themeState,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Send',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        customBorder: const CircleBorder(),
        hoverColor: enabled ? Colors.transparent : themeState.bgHover,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: enabled ? 32 : 30,
              height: enabled ? 32 : 30,
              decoration: BoxDecoration(
                color: enabled ? themeState.primary : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                size: 19,
                color: enabled
                    ? themeState.onPrimary
                    : themeState.textQuaternary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
