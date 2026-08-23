/// What makes a central handle valid, in one place.
///
/// A handle is checked twice: once by whatever screen is asking for it, so the
/// user is told before a round trip, and once by [CentralDmCubit] before it
/// calls the directory. Those two answers have to agree — a field that accepts
/// something the cubit then rejects reads as the app losing the input — so the
/// rule and the sentence explaining it live here rather than at either site.
///
/// Lowercase and trimmed rather than rejected: people type a leading space or
/// capitalise out of habit, and there is nothing to be gained by refusing a
/// handle over something we can fix ourselves. The directory is case-folded, so
/// `Noor` and `noor` were never going to be two accounts anyway.
class CentralHandle {
  const CentralHandle._();

  static const int minLength = 3;
  static const int maxLength = 20;

  /// The rule as a sentence, for hints and error text.
  static const String rule =
      'Handles are $minLength–$maxLength characters: a–z, 0–9, underscore.';

  /// Built from the bounds above so the two can't drift apart.
  static final RegExp _pattern = RegExp('^[a-z0-9_]{$minLength,$maxLength}\$');

  static String normalize(String raw) => raw.trim().toLowerCase();

  static bool isValid(String raw) => _pattern.hasMatch(normalize(raw));
}
