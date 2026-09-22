import 'dart:async';

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
import '../../../../logic/services/link_preview_fetcher.dart';
import '../../../../logic/services/link_preview_parser.dart';
import '../../../../logic/services/mention_suggestions.dart';
import '../../../../logic/services/voice_note_recorder.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/theme_context.dart';
import '../../emoji_text.dart';
import '../../tap_to_focus.dart';
import 'composer_command_menu.dart';
import 'composer_input_row.dart';
import 'composer_link_preview.dart';
import 'composer_mention_menu.dart';
import 'composer_plaintext_notice.dart';
import 'composer_recording_bar.dart';
import 'composer_reply_bar.dart';
import 'composer_staged_row.dart';

/// Message input row: attach + emoji buttons, the text field, a mic and the
/// send button, with a strip of staged-attachment chips above it once files
/// are picked. The emoji button opens a popover picker.
///
/// Enter sends, Shift+Enter inserts a newline (desktop convention). A message
/// with neither text nor attachments never sends. [footer] is an optional slot
/// below the bar — central DMs put the quota meter there.
part 'chat_composer_attachments.dart';
part 'chat_composer_link_preview.dart';
part 'chat_composer_recording.dart';

class ChatComposer extends StatefulWidget {
  /// Called with the trimmed text, any staged attachments, and the preview
  /// this device built for the first link — null when there was none, it
  /// was dismissed, or previews are off.
  final void Function(
    String text,
    List<PendingAttachment> attachments,
    PendingLinkPreview? preview,
  )
  onSend;

  /// Who can be named, asked of the server for what has been typed after the
  /// `@` (`011_directory.sql`).
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

  /// Per-file size cap for this surface, in bytes.
  ///
  /// Checked here so an oversized file is refused with a sentence at the
  /// moment it is picked, rather than after it has been read, encrypted and
  /// pushed at a bucket that answers 413. The bucket's own `file_size_limit`
  /// is still the enforcement — this is the courtesy.
  final int maxAttachmentBytes;

  /// What the server has room for in total (migration 029), or null when it
  /// has no storage limit. Advisory: a trigger on the storage table is what
  /// actually refuses, and this only exists so the refusal arrives as a
  /// sentence before the upload rather than an HTTP 500 after it.
  final int? remainingStorageBytes;

  const ChatComposer({
    super.key,
    required this.onSend,
    this.onTyping,
    this.hintText = 'Send a message',
    this.enabled = true,
    this.footer,
    this.maxAttachmentBytes = ServerLimits.defaultMaxAttachmentBytes,
    this.remainingStorageBytes,
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
        _ComposerLinkPreviewMixin {
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

  /// The `@` fragment the caret is inside, or null when it is not in one.
  ///
  /// Null while recording or disabled, and null where there is nobody to name —
  /// see [MentionSuggestions.queryAt], which is also what decides that
  /// `a@b.com` is an address rather than a name.
  String? get _mentionQueryAt {
    if (!widget.enabled || _isRecording || widget.onMentionSearch == null) {
      return null;
    }
    return MentionSuggestions.queryAt(
      _controller.text,
      _controller.selection.baseOffset,
    );
  }

  /// Who the `@` menu should be offering: the server's candidates for the
  /// current fragment, ranked and capped locally.
  ///
  /// Ranked here as well as there on purpose. The local pass is what narrows
  /// the menu on the very next keystroke, before the request for it has come
  /// back — and because the two use the same rule (prefix beats substring,
  /// spaces squashed out of a display name) the rows do not jump when the
  /// answer lands. It is also where the sender is dropped and the menu is cut
  /// to four.
  List<ServerMember> get _mentionMatches {
    final query = _mentionQueryAt;
    if (query == null) return const [];
    return MentionSuggestions.suggest(
      query,
      _mentionCandidates,
      excludeUserId: widget.selfUserId,
    );
  }

  /// Display name → username for everyone picked from the menu.
  ///
  /// The field shows the name the room knows; the message has to carry the
  /// username. This is what remembers which person a given display name meant,
  /// so [MentionSuggestions.toWire] never has to guess between two people who
  /// happen to be called the same thing.
  final Map<String, String> _picked = {};

  /// Put the chosen person's *display name* in the field, and remember who it
  /// was — see [MentionSuggestions.apply].
  void _pickMention(ServerMember member) {
    final result = MentionSuggestions.apply(
      _controller.text,
      _controller.selection.baseOffset,
      member,
    );
    _picked[member.displayName] = member.username;
    _controller.text = result.text;
    _controller.selection = TextSelection.collapsed(offset: result.cursor);
    _focusNode.requestFocus();
    setState(() {});
  }

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

  /// Anchors the floating `@` menu to the composer bar.
  final LayerLink _menuLink = LayerLink();
  final OverlayPortalController _menuOverlay = OverlayPortalController();

  /// Who the `@` menu is currently offering.
  ///
  /// Held rather than computed in `build` because showing an overlay is not
  /// something a build may do — and because the menu has to react to the caret
  /// moving, which `onChanged` never reports.
  List<ServerMember> _mentions = const [];

  /// The server's answer for the fragment in [_candidatesFor].
  ///
  /// Kept across keystrokes so the menu narrows immediately while the next
  /// answer is in flight. Typing another letter can only ever *shrink* the set
  /// of names that match, so filtering what we already hold is never wrong —
  /// it is only, briefly, incomplete.
  List<ServerMember> _mentionCandidates = const [];

  /// The fragment [_mentionCandidates] answers, so a repeated one is not asked
  /// for twice.
  String? _candidatesFor;

  Timer? _mentionDebounce;

  /// Guards a slow search landing after a newer one.
  int _mentionRequestId = 0;

  /// Short, because this fires while somebody is watching the menu. Long
  /// enough that typing a name straight through is one request rather than
  /// six.
  static const Duration _mentionSearchDelay = Duration(milliseconds: 160);

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

  /// Ask the server who matches the fragment the caret is in.
  void _refreshMentionCandidates(String? query) {
    if (query == _candidatesFor) return;
    _candidatesFor = query;
    _mentionDebounce?.cancel();
    if (query == null) {
      _mentionCandidates = const [];
      return;
    }
    _mentionDebounce = Timer(_mentionSearchDelay, () async {
      final id = ++_mentionRequestId;
      final found = await widget.onMentionSearch!(query);
      if (!mounted || id != _mentionRequestId) return;
      setState(() => _mentionCandidates = found);
      _syncMentionMenu();
    });
  }

  /// Recompute the `@` menu, and open or close the overlay to match.
  void _syncMentionMenu() {
    _refreshMentionCandidates(_mentionQueryAt);
    final next = _mentionMatches;
    final changed =
        next.length != _mentions.length ||
        [
          for (var i = 0; i < next.length; i++) next[i].id != _mentions[i].id,
        ].any((differs) => differs);
    if (changed && mounted) setState(() => _mentions = next);

    // Guarded: this runs from a controller listener, which can outlive the
    // widget by a frame, and showing an overlay from a dead element throws.
    if (!mounted) return;
    final shouldShow = next.isNotEmpty && _suggestions.isEmpty;
    if (shouldShow != _menuOverlay.isShowing) {
      shouldShow ? _menuOverlay.show() : _menuOverlay.hide();
    }
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposeRecording();
    _mentionDebounce?.cancel();
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
    if (!widget.enabled) return;
    if (text.isEmpty && _staged.isEmpty) return;
    final attachments = List<PendingAttachment>.from(_staged);
    final preview = _takePreview();
    _controller.clear();
    _picked.clear();
    setState(_staged.clear);
    widget.onSend(text, attachments, preview);
    _focusNode.requestFocus();
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
              : ComposerStagedRow(staged: _staged, onRemove: _removeStaged),
        ),
        if (_preview != null)
          ComposerLinkPreview(preview: _preview!, onRemove: _dismissPreview),
        // Above the bar, because the point of it is to be read *before*
        // the message goes.
        if (_command != null) ComposerPlaintextNotice(bot: _command!.bot),
        if (_suggestions.isNotEmpty)
          ComposerCommandMenu(
            entries: _suggestions,

            onSelected: (_, name) => _pickCommand(name),
          ),
        _buildBar(themeState),
        if (widget.footer != null) ...[
          const SizedBox(height: 6),
          widget.footer!,
        ],
      ],
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
