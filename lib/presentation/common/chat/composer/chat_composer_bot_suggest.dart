part of 'chat_composer.dart';

/// Asking a bot what to offer while its command is typed — the songs under
/// `/play thats so tr` (WIRE.md §7, BOTS.md §4).
///
/// The one time the composer talks to a bot before Enter. It asks only for a
/// verb whose bot switched it on (`suggest` in the manifest), only once a space
/// and something after it have been typed, and only after a pause, so typing a
/// title straight through is one question rather than one per letter.
mixin _ComposerBotSuggestMixin on State<ChatComposer> {
  /// Implemented by the State class, which owns the field.
  TextEditingController get _controller;
  FocusNode get _focusNode;
  void _send();

  /// The line being asked about, so a caret move or a repeated keystroke is
  /// not asked twice.
  String? _botAskedFor;

  /// Who is being asked, and what they last answered.
  ({ServerMember bot, String command, String query})? _botQuery;
  List<BotSuggestion> _botSuggestions = const [];
  bool _botSearching = false;

  Timer? _botDebounce;

  /// Guards a slow answer landing after a newer question.
  int _botRequestId = 0;

  /// Longer than the `@` menu's: each question is a search somewhere else,
  /// and a pause in typing a title is what says it is worth one.
  static const Duration _botSuggestDelay = Duration(milliseconds: 350);

  void _disposeBotSuggest() => _botDebounce?.cancel();

  /// Recompute what to ask, and ask it after a pause. Runs on every edit.
  void _syncBotSuggest() {
    if (!mounted) return;
    final ask = widget.onCommandSuggest;
    final query = ask == null || !widget.enabled
        ? null
        : BotCommands.suggestionQuery(_controller.text, widget.bots);
    final key = query == null
        ? null
        : '${query.bot.id}/${query.command}/${query.query}';
    if (key == _botAskedFor) return;
    _botAskedFor = key;
    _botDebounce?.cancel();

    if (query == null) {
      // Off the command, or emptied after it: the menu goes, and an answer
      // still on its way is for a line that no longer exists.
      _botRequestId++;
      if (_botQuery != null || _botSuggestions.isNotEmpty || _botSearching) {
        setState(() {
          _botQuery = null;
          _botSuggestions = const [];
          _botSearching = false;
        });
      }
      return;
    }

    // Another bot or verb: what the last one offered does not apply.
    final sameAsker =
        _botQuery?.bot.id == query.bot.id &&
        _botQuery?.command == query.command;
    setState(() {
      _botQuery = query;
      _botSearching = true;
      if (!sameAsker) _botSuggestions = const [];
    });
    _botDebounce = Timer(_botSuggestDelay, () async {
      final id = ++_botRequestId;
      final found = await ask!(query.bot, query.command, query.query);
      if (!mounted || id != _botRequestId) return;
      setState(() {
        _botSuggestions = found;
        _botSearching = false;
      });
    });
  }

  /// Send the command with the picked row's value in place of what was typed.
  void _pickBotSuggestion(BotSuggestion suggestion) {
    final query = _botQuery;
    if (query == null) return;
    _controller.text = '/${query.command} ${suggestion.value}';
    _send();
    _focusNode.requestFocus();
  }

  /// Whether the menu is up. Also when the answer was nothing, so it can say
  /// so: a menu that simply never appeared reads as the feature not working.
  bool get _showsBotSuggestions => _botQuery != null;
}
