import 'package:flutter/services.dart';

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

  /// Fold the field as it is typed, into exactly what [normalize] would
  /// claim.
  ///
  /// Here rather than at each field because the fold is [normalize]'s
  /// behaviour, not a keyboard restriction: a plain allow-list would refuse
  /// the capital that this class has always been willing to fix. Showing the
  /// fold instead means the box and the account agree — `Noor` becomes `noor`
  /// under the cursor rather than at submit, and a space or a `!` never
  /// arrives to be silently dropped later.
  static final List<TextInputFormatter> inputFormatters = [
    _FoldToHandle(),
  ];
}

class _FoldToHandle extends TextInputFormatter {
  static final _disallowed = RegExp(r'[^a-z0-9_]');

  static String _fold(String raw) =>
      raw.toLowerCase().replaceAll(_disallowed, '');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue previous,
    TextEditingValue next,
  ) {
    final folded = _fold(next.text);
    if (folded == next.text) return next;
    // Where the caret lands is counted through the same fold, not carried
    // over: dropping two characters from the middle of a paste moves
    // everything after them, and an offset taken from the unfolded text
    // would put the caret past the end of the field.
    final caret = next.selection.baseOffset < 0
        ? next.text.length
        : next.selection.baseOffset;
    return TextEditingValue(
      text: folded,
      selection: TextSelection.collapsed(
        offset: _fold(next.text.substring(0, caret)).length,
      ),
    );
  }
}
