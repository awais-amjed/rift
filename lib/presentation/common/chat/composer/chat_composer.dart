import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/classes/chat_message.dart';
import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/attachment_staging.dart';
import '../../../../logic/services/bot_command.dart';
import '../../../../logic/services/file_save/save_target.dart';
import '../../../../logic/services/host_platform.dart';
import '../../../../logic/services/link_preview_fetcher.dart';
import '../../../../logic/services/link_preview_parser.dart';
import '../../../../logic/services/mention_suggestions.dart';
import '../../../../logic/services/voice_note_recorder.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/theme_context.dart';
import '../../emoji_text.dart';
import '../../tap_to_focus.dart';
import '../drop/chat_drop_relay.dart';
import 'composer_channel_plain_notice.dart';
import 'composer_command_menu.dart';
import 'composer_input_row.dart';
import 'composer_link_preview.dart';
import 'composer_mention_menu.dart';
import 'composer_plain_file_notice.dart';
import 'composer_plaintext_notice.dart';
import 'composer_recording_bar.dart';
import 'composer_reply_bar.dart';
import 'composer_staged_row.dart';

part 'chat_composer_attachments.dart';
part 'chat_composer_link_preview.dart';
part 'chat_composer_menus.dart';
part 'chat_composer_recording.dart';

/// Over the widget budget and one job: the bar, and the state its controls
/// share. Attachments, recording, link previews and the `@`/`/` menus are
/// already their own parts.
///
/// Message input row: attach + emoji buttons, the text field, a mic and the
/// send button, with a strip of staged-attachment chips above it once files
/// are picked. The emoji button opens a popover picker.
///
/// Enter sends, Shift+Enter inserts a newline (desktop convention). A message
/// with neither text nor attachments never sends. [footer] is an optional slot
/// below the bar — central DMs put the quota meter there.
class ChatComposer extends StatefulWidget {
  /// Called with the trimmed text, any staged attachments, and the preview
  /// this device is building for the first link — null when there was none,
  /// it was dismissed, or previews are off. A future, because a link sent
  /// before its card was ready waits for it (`_ComposerLinkPreviewMixin`).
  ///
  /// Completes with true when the server refused the message outright — a
  /// block, a limit, a time-out — and it is not kept anywhere to retry. The
  /// field was emptied by the same press, so the composer then puts back
  /// what was in it, unless something new has been started there meanwhile.
  final Future<bool> Function(
    String text,
    List<PendingAttachment> attachments,
    Future<PendingLinkPreview?>? preview,
  )
  onSend;

  /// Who can be named, asked of the server for what has been typed after the
  /// `@` (`search_members`).
  ///
  /// Null turns the menu off, which is right where there is nobody to name —
  /// a DM has one other person and they are the conversation.
  ///
  /// A callback rather than a list because the list is the roster, and the
  /// roster no longer fits in the client. It used to: the composer was handed
  /// every member and filtered them locally, which silently stopped finding
  /// anybody past the thousandth name. The ranking is still applied here on top
  /// of the answer — `MentionSuggestions.suggest` is what drops the sender and
  /// caps the menu — and it agrees with `search_members` by design, so the rows
  /// do not reorder themselves when the server's reply lands.
  final Future<List<ServerMember>> Function(String query)? onMentionSearch;

  /// The sender, left out of their own `@` menu: a message that pings its own
  /// author is only ever a mistake, and `Mentions.resolve` drops it anyway.
  final String? selfUserId;

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

  /// False holds the send back while the field stays usable: the
  /// conversation is still opening, so what is typed meanwhile stays in the
  /// field and goes with the first press once it has. Not [enabled] — a
  /// greyed field in the second before a conversation is ready reads as
  /// broken, and people retype into it.
  final bool canSend;

  /// Drawn flush under the bar. It carries its own top spacing, so a footer
  /// that has nothing to show — the quota meter, most of the time — takes no
  /// room and leaves the composer where a channel's sits.
  final Widget? footer;

  /// The message being answered, or null for an ordinary send. Drawn as a
  /// strip above the bar; [onCancelReply] is the only way off it.
  ///
  /// The composer takes focus whenever this *becomes* non-null, because
  /// pressing Reply is a request to type — see [didUpdateWidget].
  final ChatMessage? replyingTo;
  final VoidCallback? onCancelReply;

  /// Whether the reply will ring its author, and the toggle for it. Null
  /// where nobody can be rung: a DM has one recipient and already wakes them.
  final bool? replyPings;
  final ValueChanged<bool>? onToggleReplyPing;

  /// Whether this member may attach anything here at all. False takes the
  /// attach button and the voice-note button away — a voice note is an
  /// attachment — and says why, rather than offering a picker whose upload
  /// the server will refuse (`chat_attachments_insert`).
  final bool canAttach;

  /// Per-file size cap for this surface, in bytes.
  ///
  /// Checked here so an oversized file is refused with a sentence at the
  /// moment it is picked, rather than after it has been read, encrypted and
  /// pushed at a bucket that answers 413. The bucket's own `file_size_limit`
  /// is still the enforcement — this is the courtesy.
  final int maxAttachmentBytes;

  /// What the server has room for in total, or null when it
  /// has no storage limit. Advisory: a trigger on the storage table is what
  /// actually refuses, and this only exists so the refusal arrives as a
  /// sentence before the upload rather than an HTTP 500 after it.
  final int? remainingStorageBytes;

  /// Whether a big file may be sent unencrypted here: a self-hosted server's
  /// public channels. Not a DM or a private channel, whose files any member
  /// of a server from before `chat_attachments_select` asked about the
  /// channel can fetch; not central, whose files stop at 10 MB.
  final bool offersPlainFiles;

  /// A channel whose encryption was turned off: everything typed here goes
  /// in the clear, so it says so above the bar, and offers no choice about
  /// files, which go as they are.
  final bool notEncrypted;

  /// Start a poll. Null where there are none — DMs have two readers, and a
  /// poll of two is a question.
  final VoidCallback? onCreatePoll;

  const ChatComposer({
    super.key,
    required this.onSend,
    this.onTyping,
    this.hintText = 'Send a message',
    this.enabled = true,
    this.canSend = true,
    this.footer,
    this.canAttach = true,
    this.maxAttachmentBytes = ServerLimits.defaultMaxAttachmentBytes,
    this.remainingStorageBytes,
    this.offersPlainFiles = false,
    this.notEncrypted = false,
    this.onCreatePoll,
    this.bots = const [],
    this.onMentionSearch,
    this.selfUserId,
    this.replyingTo,
    this.onCancelReply,
    this.replyPings,
    this.onToggleReplyPing,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with
        _ComposerAttachmentsMixin,
        _ComposerRecordingMixin,
        _ComposerLinkPreviewMixin,
        _ComposerMenusMixin {
  // Colours emoji as they are typed, matching how they render once sent.
  @override
  final TextEditingController _controller = EmojiTextEditingController();
  @override
  final FocusNode _focusNode = FocusNode();
  @override
  final List<PendingAttachment> _staged = [];

  @override
  bool get _atAttachmentLimit =>
      _staged.length >= AttachmentStaging.maxPerMessage;

  @override
  void initState() {
    super.initState();
    // The bar lights its border while the field has focus.
    _focusNode.addListener(_onFocusChanged);
    // Fires for edits *and* caret moves; both change whether the caret is
    // inside a mention.
    _controller.addListener(_syncMentionMenu);
  }

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);
    // Pressing Reply on a row across the screen is a request to type, so the
    // caret comes here rather than waiting to be clicked for. Only on the
    // *transition* into a reply: firing on every rebuild would drag focus
    // back from wherever it went while the strip was still up, and answering
    // a different message while already replying is still one transition.
    final now = widget.replyingTo?.id;
    if (now != null && now != old.replyingTo?.id) _focusNode.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _claimDropRelay();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Staged files die with the composer; any that were copies go too.
    unawaited(AttachmentStaging.discard(_staged));
    _releaseDropRelay();
    _disposeRecording();
    _disposeMenus();
    _disposeLinkPreview();
    _controller.removeListener(_syncMentionMenu);
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    // The field holds display names; a mention has to travel as a username.
    final text = MentionSuggestions.toWire(_controller.text, _picked).trim();
    if (!widget.enabled || !widget.canSend) return;
    if (text.isEmpty && _staged.isEmpty) return;
    final attachments = List<PendingAttachment>.from(_staged);
    final preview = _takePreview();
    final typed = _controller.text;
    final picked = Map.of(_picked);
    _controller.clear();
    _picked.clear();
    setState(_staged.clear);
    unawaited(
      widget.onSend(text, attachments, preview).then((refused) {
        if (refused) _giveBack(typed, picked, attachments);
      }),
    );
    _focusNode.requestFocus();
  }

  /// Put a refused message back as it was typed: the field's own text (names,
  /// not the usernames it was sent as), the names picked from the menu, and
  /// the files. Only into an empty composer — words typed since are newer than
  /// the ones that bounced, and overwriting them would lose those instead.
  void _giveBack(
    String typed,
    Map<String, String> picked,
    List<PendingAttachment> attachments,
  ) {
    if (!mounted || _controller.text.isNotEmpty || _staged.isNotEmpty) {
      // Nowhere to put the files back, so their copies have no reader left.
      unawaited(AttachmentStaging.discard(attachments));
      return;
    }
    _picked.addAll(picked);
    _controller.value = TextEditingValue(
      text: typed,
      selection: TextSelection.collapsed(offset: typed.length),
    );
    setState(() => _staged.addAll(attachments));
    _syncLinkPreview(typed);
  }

  void _onTextChanged(String value) {
    // Rebuild so the send button enables/disables.
    setState(() {});
    if (value.trim().isNotEmpty) widget.onTyping?.call();
    _syncLinkPreview(value);
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // The mention menu floats rather than sitting in the column: a list
    // that took layout space shoved the whole conversation up as somebody
    // typed a name, and dropped it back on every keystroke that narrowed
    // the list. A popup that covers the last message costs nothing — it is
    // gone by the time you read it.
    //
    // The `/` menu still takes space, and should: it only ever opens on an
    // empty composer, where there is no message right above it to hide.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Builder(
        builder: (context) {
          return CompositedTransformTarget(
            link: _menuLink,
            child: OverlayPortal(
              controller: _menuOverlay,
              // In the app's overlay rather than in this subtree, because a
              // child drawn outside its parent's box paints but does not
              // hit-test — the menu appeared and could not be clicked.
              overlayChildBuilder: (context) => CompositedTransformFollower(
                link: _menuLink,
                // The menu's bottom edge sits on the composer's top edge.
                targetAnchor: Alignment.topLeft,
                followerAnchor: Alignment.bottomLeft,
                // Shrink-wrapped: an overlay child is handed the whole
                // screen to fill, and a popup that took it covered the
                // conversation entirely instead of sitting above the bar.
                // The menu sets its own width, like every other popover.
                child: Align(
                  alignment: Alignment.bottomLeft,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: ComposerMentionMenu(
                    members: _mentions,

                    onSelected: _pickMention,
                  ),
                ),
              ),
              child: _buildColumn(themeState),
            ),
          );
        },
      ),
    );
  }

  Widget _buildColumn(ThemeState themeState) {
    final replyingTo = widget.replyingTo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Above everything else on the stack, including the staged chips: it
        // says which conversation this message joins, and that is the first
        // thing to read, not the last.
        if (replyingTo != null && widget.onCancelReply != null)
          ComposerReplyBar(
            replyingTo: replyingTo,
            onCancel: widget.onCancelReply!,
            pinging: widget.replyPings,
            onTogglePing: widget.onToggleReplyPing,
          ),
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
                  onRemove: _removeStaged,
                  onTogglePlain: widget.offersPlainFiles ? _togglePlain : null,
                ),
        ),
        // Above the bar for the same reason as the bot notice below: it has
        // to be read while the file can still be switched back.
        if (_staged.any((a) => a.plain))
          ComposerPlainFileNotice(count: _staged.where((a) => a.plain).length),
        if (_preview != null)
          ComposerLinkPreview(preview: _preview!, onRemove: _dismissPreview),
        // Above the bar, because the point of it is to be read *before*
        // the message goes.
        if (_command != null)
          ComposerPlaintextNotice(bot: _command!.bot)
        else if (widget.notEncrypted)
          const ComposerChannelPlainNotice(),
        if (_suggestions.isNotEmpty)
          ComposerCommandMenu(
            entries: _suggestions,

            onSelected: (_, name) => _pickCommand(name),
          ),
        _buildBar(themeState),
        // No gap of its own: a footer with nothing to say draws nothing, and
        // a fixed 6px here kept the composer lifted over an empty meter.
        ?widget.footer,
      ],
    );
  }

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
      duration: AppMotion.state,
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: themeState.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusCard),
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

              onCancel: _cancelRecording,
              onStop: _stopRecording,
            )
          : ComposerInputRow(
              controller: _controller,
              focusNode: _focusNode,

              enabled: widget.enabled,
              canSend:
                  widget.enabled &&
                  widget.canSend &&
                  (_controller.text.trim().isNotEmpty || _staged.isNotEmpty),
              atAttachmentLimit: _atAttachmentLimit,
              canAttach: widget.canAttach,
              hintText: widget.hintText,
              onChanged: _onTextChanged,
              onSubmit: _send,
              onAcceptSuggestion: _acceptSuggestion,
              onPickFiles: _pickFiles,
              onCreatePoll: widget.onCreatePoll,
              onStartRecording: _startRecording,
              onEmojiInserted: () => setState(() {}),
            ),
    );
  }
}
