part of 'chat_composer.dart';

/// The arrow keys in whichever menu is open above the composer — the `@`
/// people, the `/` commands, or a bot's suggestions.
///
/// Up and Down belong to the menu while one is showing: they used to move the
/// caret through the line instead, which in a one-line command is nowhere, so
/// the only way to a row was the mouse. Enter and Tab then take the row they
/// are on.
///
/// Before an arrow is pressed nothing changes: Enter takes the first row of
/// the `@` and `/` menus as it always has, and under a bot's suggestions it
/// sends the line as typed — the bot plays its best match, which is what
/// somebody who never looked at the list meant.
mixin _ComposerMenuKeysMixin
    on State<ChatComposer>, _ComposerMenusMixin, _ComposerBotSuggestMixin {
  int? _highlight;

  /// Which menu, showing what, [_highlight] was set in. A highlight belongs to
  /// one list: typing a letter, or a new answer from the bot, is a different
  /// list, and row 3 of the old one is not row 3 of the new.
  String? _highlightIn;

  /// What the open menu is, as a value that changes when its rows do; null
  /// when none is open. In the order [_acceptSuggestion] picks from.
  String? get _openMenu {
    if (_mentions.isNotEmpty) {
      return '@ ${_mentions.map((m) => m.id).join(' ')}';
    }
    final commands = _suggestions;
    if (commands.isNotEmpty) {
      return '/ ${commands.map((c) => '${c.bot.id}/${c.name}').join(' ')}';
    }
    if (_showsBotSuggestions && _botSuggestions.isNotEmpty) {
      // Each answer is a new list, and a new list is a new menu.
      return 'bot ${identityHashCode(_botSuggestions)}';
    }
    return null;
  }

  int get _openMenuLength {
    if (_mentions.isNotEmpty) return _mentions.length;
    final commands = _suggestions;
    if (commands.isNotEmpty) return commands.length;
    if (_showsBotSuggestions) return _botSuggestions.length;
    return 0;
  }

  /// The row the arrows are on in the menu showing now, or null.
  int? get _highlighted {
    final menu = _openMenu;
    if (menu == null || menu != _highlightIn) return null;
    final at = _highlight;
    return at != null && at < _openMenuLength ? at : null;
  }

  /// Down is +1, Up is -1. Answers false when no menu is open, which leaves
  /// the key to the field.
  bool _moveHighlight(int delta) {
    final menu = _openMenu;
    final length = _openMenuLength;
    if (menu == null || length == 0) return false;
    final current = _highlighted;
    setState(() {
      _highlightIn = menu;
      // The first press lands on an end: Down on the first row, Up on the
      // last. Past either end it comes round again.
      _highlight = current == null
          ? (delta > 0 ? 0 : length - 1)
          : (current + delta) % length;
    });
    return true;
  }

  @override
  bool _acceptSuggestion({bool sending = false}) {
    final i = _highlighted;
    if (i != null) {
      _highlight = null;
      if (_mentions.isNotEmpty) {
        _pickMention(_mentions[i]);
        return true;
      }
      final commands = _suggestions;
      if (commands.isNotEmpty) {
        _pickCommand(commands[i].name);
        return true;
      }
      if (_showsBotSuggestions) {
        _pickBotSuggestion(_botSuggestions[i]);
        return true;
      }
    }
    return super._acceptSuggestion(sending: sending);
  }
}
