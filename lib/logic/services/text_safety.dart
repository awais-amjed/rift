import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One entry of the bundled profanity list (dsojevic/profanity-list, MIT).
///
/// `match` is a `|`-separated set of spellings where `x*` means one or more
/// of `x`; `exceptions` are larger words the match may sit inside without
/// meaning anything, written with `*` standing for the match itself.
class ProfanityRule {
  final String id;
  final List<String> spellings;
  final int severity;
  final List<String> tags;
  final List<String> exceptions;

  const ProfanityRule({
    required this.id,
    required this.spellings,
    required this.severity,
    this.tags = const [],
    this.exceptions = const [],
  });

  factory ProfanityRule.fromJson(Map<String, dynamic> json) => ProfanityRule(
    id: json['id'] as String,
    spellings: (json['match'] as String).split('|'),
    severity: (json['severity'] as num).toInt(),
    tags: [for (final t in json['tags'] as List? ?? const []) t as String],
    exceptions: [
      for (final e in json['exceptions'] as List? ?? const []) e as String,
    ],
  );
}

/// What the list made of one message.
class TextSafetyVerdict {
  final ProfanityRule rule;
  const TextSafetyVerdict(this.rule);

  /// Covered from "medium" up. Mild — the list's own word for `damn`,
  /// `hell`, `crap` — is how people talk, and covering it would train
  /// everybody to tap through covers, which is the one thing a cover must
  /// not do.
  static const int coverSeverity = 2;

  bool get isSensitive => rule.severity >= coverSeverity;
}

/// The on-device profanity check: a word list, not a model.
///
/// Small on purpose. A classifier that understands context weighs tens of
/// megabytes and is wrong on ordinary speech often enough that its verdicts
/// are opinions; a list is 60 KB, explainable, and wrong only in the ways a
/// list is wrong — which the normaliser below narrows. It runs on the device
/// that decrypted the message and nowhere else, like the image classifier.
///
/// Whole tokens only. The list allows matching inside larger words with an
/// exceptions mechanism to catch `class` and `assist`; that is a fight no
/// list wins, so a match has to start and end at a word boundary here.
class TextSafety {
  TextSafety._();

  static final TextSafety instance = TextSafety._();

  static const String asset = 'assets/models/profanity_en.json';

  List<_Compiled> _rules = const [];
  RegExp? _any;
  bool get isLoaded => _any != null;

  /// Verdicts by message id and text, so a rebuilt row does not rescan.
  final Map<String, TextSafetyVerdict?> _verdicts = {};

  /// Covered words by message id and text, for the same reason.
  final Map<String, List<({int start, int end})>> _ranges = {};

  /// Load the bundled list. Called once at startup and not awaited: until it
  /// lands, every message is shown.
  Future<void> load() async {
    if (isLoaded) return;
    try {
      final raw = await rootBundle.loadString(asset);
      install(json.decode(raw) as List);
    } catch (e) {
      debugPrint('TextSafety: list unavailable – $e');
    }
  }

  /// Replace the rules with [entries], as the JSON list has them.
  @visibleForTesting
  void install(List<dynamic> entries) {
    _rules = [
      for (final e in entries)
        _Compiled(ProfanityRule.fromJson(e as Map<String, dynamic>)),
    ]..sort((a, b) => b.rule.severity.compareTo(a.rule.severity));
    _any = RegExp(
      '(?<![a-z0-9])(?:${_rules.map((r) => r.source).join('|')})(?![a-z0-9])',
    );
    _verdicts.clear();
    _ranges.clear();
  }

  /// The verdict for [text], or null where nothing matched or the list has
  /// not loaded. [id] is the cache key; the text is part of it so an edit
  /// is looked at afresh.
  TextSafetyVerdict? check(String id, String text) {
    if (!isLoaded || text.isEmpty) return null;
    final key = '$id:${text.hashCode}';
    if (_verdicts.containsKey(key)) return _verdicts[key];
    if (_verdicts.length > 4000) _verdicts.clear();

    final verdict = _scan(text);
    _verdicts[key] = verdict;
    return verdict;
  }

  /// Where in [text] the words to cover are, as ranges of [text] itself —
  /// empty where nothing sensitive matched.
  ///
  /// The list matches against a normalised copy whose offsets are not the
  /// message's, so this works in words instead: the smallest run of words
  /// that matches on its own is covered, and every word in it. One word for
  /// `fuck`, two for `god damn`, four for `f u c k`. A match no run up to
  /// [_widestRun] explains covers every word, because a message that is
  /// flagged and shows nothing flagged is the one outcome that must not
  /// happen.
  List<({int start, int end})> sensitiveRanges(String id, String text) {
    if (!isLoaded || text.isEmpty) return const [];
    final key = '$id:${text.hashCode}';
    final cached = _ranges[key];
    if (cached != null) return cached;
    if (_ranges.length > 4000) _ranges.clear();

    return _ranges[key] = _locate(text);
  }

  static const int _widestRun = 16;

  /// A word as the normaliser sees one: letters, digits and the symbols
  /// leetspeak spells with, and `!` only between them — at the end of a word
  /// it is punctuation, and covering it would say more than the word did.
  static final RegExp _word = RegExp(
    r'[\p{L}\p{N}@$]+(?:!+[\p{L}\p{N}@$]+)*',
    unicode: true,
  );

  List<({int start, int end})> _locate(String text) {
    if (!(_scan(text)?.isSensitive ?? false)) return const [];
    final words = _word.allMatches(text).toList();
    final covered = List.filled(words.length, false);
    var found = false;
    // Narrowest first, so a run is only covered when nothing inside it was.
    for (var width = 1; width <= _widestRun; width++) {
      for (var i = 0; i + width <= words.length; i++) {
        if (covered.sublist(i, i + width).contains(true)) continue;
        final run = text.substring(words[i].start, words[i + width - 1].end);
        if (_scan(run)?.isSensitive ?? false) {
          covered.fillRange(i, i + width, true);
          found = true;
        }
      }
    }
    return [
      for (var i = 0; i < words.length; i++)
        if (covered[i] || !found) (start: words[i].start, end: words[i].end),
    ];
  }

  /// [text] with every character in [ranges] replaced by a dot, so a covered
  /// word keeps its place in the sentence and nothing else of itself.
  static String cover(String text, List<({int start, int end})> ranges) {
    if (ranges.isEmpty) return text;
    final out = StringBuffer();
    var at = 0;
    for (final r in ranges) {
      out
        ..write(text.substring(at, r.start))
        ..write('•' * (r.end - r.start));
      at = r.end;
    }
    return (out..write(text.substring(at))).toString();
  }

  TextSafetyVerdict? _scan(String text) {
    final forms = normalize(text);
    for (final form in forms) {
      if (!_any!.hasMatch(form)) continue;
      // Only now find which rule, most severe first.
      for (final rule in _rules) {
        if (rule.matches(form)) return TextSafetyVerdict(rule.rule);
      }
    }
    return null;
  }

  /// The forms of [text] the list is matched against.
  ///
  /// Lowercased, leetspeak undone, letters that were spaced out to dodge a
  /// filter pulled back together, punctuation between words made into
  /// spaces. Two forms come back: one with runs of a repeated letter kept
  /// at most double, one with every run collapsed to a single letter — so
  /// `fuuuck` is found without `ass` losing its second `s`.
  @visibleForTesting
  static List<String> normalize(String text) {
    var s = _unleet(text.toLowerCase());
    // Anything that is not a letter, digit or space becomes a space.
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ');
    // `f u c k`: a run of spaced single letters is one word. Except a
    // leading `a` or `i`, the only single-letter words English has — in
    // `such a c u n t` the article is not part of the disguise.
    s = s.replaceAllMapped(
      RegExp(r'(?<![a-z0-9])(?:[a-z0-9] ){2,}[a-z0-9](?![a-z0-9])'),
      (m) {
        final run = m[0]!;
        final keepsArticle =
            (run.startsWith('a ') || run.startsWith('i ')) && run.length >= 7;
        return keepsArticle
            ? '${run.substring(0, 2)}${run.substring(2).replaceAll(' ', '')}'
            : run.replaceAll(' ', '');
      },
    );
    s = s.replaceAll(RegExp(r' +'), ' ').trim();
    final doubled = s.replaceAllMapped(
      RegExp(r'([a-z0-9])\1{2,}'),
      (m) => '${m[1]}${m[1]}',
    );
    final single = s.replaceAllMapped(RegExp(r'([a-z0-9])\1+'), (m) => m[1]!);
    return doubled == single ? [doubled] : [doubled, single];
  }

  /// Leetspeak back to letters, but only where a symbol is standing in for
  /// one: touching a letter on at least one side. A `1` in `2024` or a `$`
  /// in `$5` is left alone, and `!` counts only *between* letters — at the
  /// end of a word it is the exclamation mark it looks like.
  static String _unleet(String s) {
    final out = StringBuffer();
    final chars = s.split('');
    bool letter(int i) =>
        i >= 0 && i < chars.length && _isLetter.hasMatch(chars[i]);
    var prevWasWord = false;
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      final mapped = _leetMap[c];
      if (mapped != null) {
        final inside = prevWasWord && letter(i + 1);
        final touching = prevWasWord || letter(i + 1);
        if (c == '!' ? inside : touching) {
          out.write(mapped);
          prevWasWord = true;
          continue;
        }
      }
      out.write(c);
      prevWasWord = _isLetter.hasMatch(c);
    }
    return out.toString();
  }

  static final RegExp _isLetter = RegExp(r'[a-z]');
  static const Map<String, String> _leetMap = {
    '@': 'a',
    r'$': 's',
    '!': 'i',
    '0': 'o',
    '1': 'i',
    '3': 'e',
    '4': 'a',
    '5': 's',
    '7': 't',
  };
}

/// A rule with its spellings turned into one regular expression, plus the
/// exceptions it must not fire inside.
class _Compiled {
  final ProfanityRule rule;
  final String source;
  final RegExp _own;
  final List<RegExp> _exceptions;

  _Compiled(this.rule)
    : source = rule.spellings.map(_spelling).join('|'),
      _own = RegExp(
        '(?<![a-z0-9])(?:${rule.spellings.map(_spelling).join('|')})(?![a-z0-9])',
      ),
      _exceptions = [
        for (final e in rule.exceptions)
          RegExp(
            '(?<![a-z0-9])${e.split('*').map(RegExp.escape).join('(?:${rule.spellings.map(_spelling).join('|')})')}(?![a-z0-9])',
          ),
      ];

  bool matches(String form) {
    if (!_own.hasMatch(form)) return false;
    // An exception is a bigger word the match lives inside harmlessly. With
    // whole-token matching those are already out of reach, but a phrase
    // exception can still describe a run of words, so honour them all.
    for (final exception in _exceptions) {
      if (exception.hasMatch(form)) return false;
    }
    return true;
  }

  /// `di*ck` → `di+ck`, everything else escaped. A space in a phrase stays
  /// a single space, which is what the normaliser leaves between words.
  static String _spelling(String spelling) {
    final out = StringBuffer();
    final chars = spelling.toLowerCase().split('');
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      if (c == '*') continue;
      final repeated = i + 1 < chars.length && chars[i + 1] == '*';
      out.write(RegExp.escape(c));
      if (repeated) out.write('+');
    }
    return out.toString();
  }
}
