/// What makes a username on a server valid, in one place.
///
/// The sibling of [CentralHandle] — a *central handle* names one account
/// across the whole network, a *username* names you on one server, and the two
/// are set by different forms. This is the second rule, not a copy of the
/// first: a server's namespace is its own, so a handle taken on central says
/// nothing about a username here, and the shapes are allowed to differ.
///
/// **The shape is the mention parser's, and that is the whole constraint.**
/// A username is what `@`-mentions resolve against
/// (`message_markup.dart`'s `^@([A-Za-z0-9_.-]{1,32})`, and
/// `MentionSuggestions`, which refuses a query containing whitespace). A
/// username the parser cannot express is a member nobody can mention and
/// search cannot reach — which is what "Benny Smith!" was, accepted by a field
/// that only checked the box was not empty.
///
/// Trimmed rather than rejected for surrounding space, as [CentralHandle]
/// does; case is kept, because a server username is shown as typed.
library;

import 'central_handle.dart';

class ServerUsername {
  const ServerUsername._();

  static const int minLength = 2;

  /// The mention parser's own ceiling, so anything valid here is mentionable.
  static const int maxLength = 32;

  /// The rule as a sentence, for hints and error text.
  static const String rule =
      'Usernames are $minLength–$maxLength characters: letters, numbers, '
      'underscore, dot or hyphen — no spaces.';

  /// Built from the bounds above so the two can't drift apart. Kept in step
  /// with the mention pattern in `message_markup.dart`.
  static final RegExp _pattern = RegExp(
    '^[A-Za-z0-9_.-]{$minLength,$maxLength}\$',
  );

  static String normalize(String raw) => raw.trim();

  static bool isValid(String raw) => _pattern.hasMatch(normalize(raw));

  /// The error to show, or null when [raw] is fine. One sentence per reason
  /// rather than the whole rule every time: somebody who typed a space wants
  /// to be told about the space.
  static String? errorFor(String raw) {
    final name = normalize(raw);
    if (name.isEmpty) return 'Pick a username.';
    if (name.length < minLength) {
      return 'Usernames are at least $minLength characters.';
    }
    if (name.length > maxLength) {
      return 'Usernames are at most $maxLength characters.';
    }
    if (name.contains(RegExp(r'\s'))) {
      return "Usernames can't contain spaces.";
    }
    if (!isValid(name)) {
      return 'Letters, numbers, underscore, dot and hyphen only.';
    }
    return null;
  }

  /// A central handle always satisfies this rule, which is why the join form
  /// can prefill one. Asserted by a test rather than assumed.
  static bool acceptsCentralHandles() =>
      isValid('a' * CentralHandle.minLength) &&
      isValid('a' * CentralHandle.maxLength);
}
