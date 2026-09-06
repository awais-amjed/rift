/// Turning a message body into the stretches it should be drawn as.
///
/// Rift's markup is the small Discord-flavoured set people actually type —
/// `**bold**`, `*italic*`, `_italic_`, `~~strike~~`, `` `code` `` and fenced
/// blocks — plus `@mentions`, parsed in the same pass because a mention can sit
/// inside bold and two passes would have to agree about which one owned it.
///
/// Deliberately not a Markdown implementation. There is no `[text](url)`,
/// no headings, no lists: a chat line is not a document, and every construct
/// added here is one more way for someone's plain text to come out looking
/// like something they did not write. A bare `http(s)://` address is the one
/// exception — it is recognised as itself, never rewritten, and made
/// tappable.
///
/// Pure, so the awkward parts — unmatched delimiters, `snake_case`, code that
/// contains asterisks — are reachable in a test rather than only by typing into
/// a running app.
library;

import '../../data/classes/markup_span.dart';

export '../../data/classes/markup_span.dart';

/// Longest first, so `**` is never read as two `*`.
const List<(String, Marker)> _delimiters = [
  ('**', Marker.bold),
  ('~~', Marker.strike),
  ('*', Marker.italic),
  ('_', Marker.italic),
];

/// The characters a backslash may escape: everything this parser treats as
/// markup, and the backslash itself.
const Set<String> _escapable = {'*', '_', '~', '`', '@', r'\'};

/// What an `@` has to be followed by to read as a name.
///
/// Liberal on purpose — resolution happens later. Matching narrowly here would
/// mean a name this parser had never heard of silently losing its highlight.
final RegExp _mention = RegExp(r'^@([A-Za-z0-9_.-]{1,32})');

/// A bare address. `http(s)://` and nothing else: `example.com` is as likely
/// to be a filename, and a scheme the app would not open is not a link.
final RegExp _link = RegExp(r'''^https?://[^\s<>"']+''', caseSensitive: false);

/// The address at [i], with the punctuation that belongs to the sentence
/// rather than the link taken off the end, or null.
///
/// A closing bracket stays when it balances one inside the address, which
/// is how Wikipedia writes half its URLs.
String? linkAt(String s, int i) {
  final m = _link.firstMatch(s.substring(i));
  if (m == null) return null;
  var raw = m.group(0)!;
  while (raw.isNotEmpty && '.,;:!?)]}'.contains(raw[raw.length - 1])) {
    if (raw.endsWith(')') && raw.contains('(')) break;
    raw = raw.substring(0, raw.length - 1);
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) return null;
  return raw;
}

/// Splits [input] into the stretches it should be drawn as.
///
/// Anything that doesn't parse is returned as the literal text that was typed.
/// That is the whole contract: a message never loses characters to markup it
/// didn't mean, and an unclosed `**` is just two asterisks.
List<MarkupSpan> parseMessageMarkup(String input) {
  if (input.isEmpty) return const [];
  final out = <MarkupSpan>[];
  _parse(input, const {}, out);
  return _merge(out);
}

void _parse(String s, Set<Marker> marks, List<MarkupSpan> out) {
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isEmpty) return;
    out.add(MarkupSpan(buffer.toString(), marks: marks));
    buffer.clear();
  }

  var i = 0;
  while (i < s.length) {
    // A backslash makes the next character literal — but only where that
    // character *is* markup. Escaping anything at all would eat the separators
    // out of `C:\Users\me`, and someone pasting a path has not asked for any
    // of this.
    if (s[i] == r'\' && i + 1 < s.length && _escapable.contains(s[i + 1])) {
      buffer.write(s[i + 1]);
      i += 2;
      continue;
    }

    // Code first, and never recursed into: the point of code is that what is
    // inside it is not markup.
    final fence = _codeSpan(s, i);
    if (fence != null) {
      flush();
      if (fence.text.isNotEmpty) {
        out.add(MarkupSpan(fence.text, marks: {...marks, Marker.code}));
      }
      i = fence.end;
      continue;
    }

    final marked = _markedSpan(s, i, marks);
    if (marked != null) {
      flush();
      _parse(marked.text, {...marks, marked.marker!}, out);
      i = marked.end;
      continue;
    }

    // An address is one stretch: no markup is read inside it, so an
    // underscore in a path does not start italics halfway through a link.
    if (s[i] == 'h' && !_isWordish(s, i - 1)) {
      final link = linkAt(s, i);
      if (link != null) {
        flush();
        out.add(MarkupSpan(link, marks: marks, link: link));
        i += link.length;
        continue;
      }
    }
    // Not preceded by a word character, or `a@b.com` reads as a mention of
    // "b.com" and every email address in a message lights up.
    if (s[i] == '@' && !_isWordish(s, i - 1)) {
      final m = _mention.firstMatch(s.substring(i));
      if (m != null) {
        flush();
        out.add(MarkupSpan(m.group(0)!, marks: marks, mention: m.group(1)));
        i += m.group(0)!.length;
        continue;
      }
    }

    buffer.write(s[i]);
    i++;
  }
  flush();
}

class _Match {
  final String text;
  final int end;
  final Marker? marker;
  const _Match(this.text, this.end, [this.marker]);
}

/// A fenced block or an inline code span starting at [i], or null.
_Match? _codeSpan(String s, int i) {
  for (final fence in const ['```', '`']) {
    if (!s.startsWith(fence, i)) continue;
    final close = s.indexOf(fence, i + fence.length);
    if (close < 0) continue; // unclosed: it is a literal backtick
    var text = s.substring(i + fence.length, close);
    // A fenced block usually arrives with newlines hugging the fences, and a
    // leading blank line in the rendered box looks like a bug.
    if (fence == '```') text = text.replaceAll(RegExp(r'^\n|\n$'), '');
    return _Match(text, close + fence.length);
  }
  return null;
}

/// A `**bold**`-style run starting at [i], or null.
_Match? _markedSpan(String s, int i, Set<Marker> marks) {
  for (final (token, marker) in _delimiters) {
    if (!s.startsWith(token, i)) continue;
    // Already inside this mark: the closer is the outer call's business.
    if (marks.contains(marker) && token != '_') continue;
    if (!_canOpen(s, i, token)) continue;

    var from = i + token.length;
    while (from < s.length) {
      final close = s.indexOf(token, from);
      if (close < 0) break;
      if (close == i + token.length) {
        // Empty inner. `**` with nothing in it is two asterisks.
        from = close + token.length;
        continue;
      }
      if (!_canClose(s, close, token)) {
        from = close + token.length;
        continue;
      }
      return _Match(
        s.substring(i + token.length, close),
        close + token.length,
        marker,
      );
    }
  }
  return null;
}

bool _isSpace(String s, int at) =>
    at < 0 || at >= s.length || RegExp(r'\s').hasMatch(s[at]);

bool _isWordish(String s, int at) =>
    at >= 0 && at < s.length && RegExp(r'[A-Za-z0-9]').hasMatch(s[at]);

/// Whether a delimiter at [i] can start a run.
///
/// It cannot when what follows is a space. That one rule is what keeps
/// `2 * 3 * 4` as arithmetic and `** **` as two pairs of asterisks rather than
/// emphasised nothing. CommonMark calls it flanking; without it, ordinary
/// prose quietly loses its punctuation to formatting nobody asked for.
///
/// Underscores carry a second rule: never inside a word. Otherwise
/// `snake_case_name` comes out half italic, and so does most of what people
/// pick for a username.
bool _canOpen(String s, int i, String token) {
  if (_isSpace(s, i + token.length)) return false;
  if (token == '_' && _isWordish(s, i - 1)) return false;
  if (_partOfLongerRun(s, i, token)) return false;
  return true;
}

/// Whether a delimiter at [i] can end a run: the mirror of [_canOpen].
bool _canClose(String s, int i, String token) {
  if (_isSpace(s, i - 1)) return false;
  if (token == '_' && _isWordish(s, i + token.length)) return false;
  if (_partOfLongerRun(s, i, token)) return false;
  return true;
}

/// Whether a one-character delimiter at [i] is really part of a longer run.
///
/// `**` that never closes must stay two asterisks, not become an italic run
/// between its own halves — which is what a lone `*` matching its neighbour
/// produces. Reading a run by its length is how CommonMark avoids the same
/// thing, and it is the difference between `**oops` rendering as typed and
/// rendering as `oops`.
bool _partOfLongerRun(String s, int i, String token) {
  if (token.length != 1) return false;
  return (i > 0 && s[i - 1] == token) ||
      (i + 1 < s.length && s[i + 1] == token);
}

/// Joins neighbours that render identically, so a plain line is one span.
List<MarkupSpan> _merge(List<MarkupSpan> spans) {
  final out = <MarkupSpan>[];
  for (final span in spans) {
    final last = out.isEmpty ? null : out.last;
    if (last != null &&
        last.mention == null &&
        span.mention == null &&
        last.link == null &&
        span.link == null &&
        last.marks.length == span.marks.length &&
        last.marks.containsAll(span.marks)) {
      out[out.length - 1] = MarkupSpan(
        last.text + span.text,
        marks: last.marks,
      );
      continue;
    }
    out.add(span);
  }
  return out;
}

/// Whether [text] names somebody in [mentionable].
///
/// Separate from rendering because the same question decides whether a message
/// is worth a notification, and answering it twice in two places is how the
/// highlight and the badge end up disagreeing.
bool mentionsAnyOf(String text, Set<String> names) {
  if (names.isEmpty) return false;
  for (final span in parseMessageMarkup(text)) {
    final mention = span.mention;
    if (mention != null && names.contains(mention.toLowerCase())) return true;
  }
  return false;
}
