part of 'chat_composer.dart';

/// The menus the composer offers as you type: `@` for a person, `/` for a
/// bot's command.
///
/// Split out because both are about what the caret is inside of, not about
/// the message: they read the field, suggest, and write a choice back. The
/// one thing they leave for sending is [_picked].
mixin _ComposerMenusMixin
    on State<ChatComposer>, _ComposerAttachmentsMixin, _ComposerRecordingMixin {
  /// Implemented by the State class, which owns the field.
  TextEditingController get _controller;
  FocusNode get _focusNode;

  void _disposeMenus() => _mentionDebounce?.cancel();

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

  /// What the `/` menu should be offering, or empty when it should be closed.
  List<({ServerMember bot, String name, String? description})>
  get _suggestions => (!widget.enabled || _isRecording)
      ? const []
      : BotCommands.suggest(_controller.text, widget.bots);

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

  /// Enter and Tab, while a menu is open: take its best row instead of
  /// sending.
  ///
  /// Both menus are ranked, so the first row is the one being offered — and
  /// with no keyboard path to it at all, Enter used to send the half-typed
  /// fragment the menu existed to finish. Answers false when nothing is open,
  /// which is what leaves Enter meaning send.
  bool _acceptSuggestion() {
    if (_mentions.isNotEmpty) {
      _pickMention(_mentions.first);
      return true;
    }
    final commands = _suggestions;
    if (commands.isNotEmpty) {
      _pickCommand(commands.first.name);
      return true;
    }
    return false;
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
}
