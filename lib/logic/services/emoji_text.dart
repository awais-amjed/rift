/// Splitting a string into text and emoji stretches so each can be rendered
/// with the font that suits it.
///
/// Why this exists: several ordinary text fonts (DejaVu Sans, Liberation,
/// Adwaita) carry *monochrome* outlines for the common emoji — 😀 U+1F600 and
/// ❤ U+2764 among them. A text font is the primary font, so it wins for every
/// codepoint it covers and the colour emoji font is never consulted. Adding a
/// colour font to `fontFamilyFallback` does **not** help: fallbacks are only
/// tried for glyphs the primary font is *missing*, which is why the rarer
/// emoji already come out in colour while the common ones render as flat white
/// glyphs. The only fix is to hand the emoji stretches to the emoji font
/// explicitly, which is what [splitEmojiRuns] enables.
library;

/// The colour-emoji font to render emoji runs with. Every desktop target ships
/// one of these, so nothing is bundled — if none resolves, the run falls back
/// to the platform default and simply looks the way it does today.
const String emojiFontFamily = 'Noto Color Emoji';

/// Tried in order when [emojiFontFamily] isn't installed.
const List<String> emojiFontFamilyFallback = [
  'Apple Color Emoji', // macOS
  'Segoe UI Emoji', // Windows
  'Twemoji Mozilla',
  'Noto Emoji',
];

/// One stretch of a string that renders with a single font.
class TextRun {
  final String text;
  final bool isEmoji;

  const TextRun(this.text, {required this.isEmoji});

  @override
  bool operator ==(Object other) =>
      other is TextRun && other.text == text && other.isEmoji == isEmoji;

  @override
  int get hashCode => Object.hash(text, isEmoji);

  @override
  String toString() => 'TextRun(${isEmoji ? 'emoji' : 'text'}: $text)';
}

const int _zwj = 0x200D;
const int _vs15 = 0xFE0E; // explicitly asks for *text* presentation
const int _vs16 = 0xFE0F; // explicitly asks for *emoji* presentation
const int _keycap = 0x20E3;

/// Splits [input] into consecutive text and emoji runs. Adjacent runs of the
/// same kind are merged, so a string with no emoji yields a single run.
List<TextRun> splitEmojiRuns(String input) {
  if (input.isEmpty) return const [];

  final cps = input.runes.toList();
  final runs = <TextRun>[];
  final buffer = StringBuffer();
  bool? bufferIsEmoji;

  void flush() {
    if (buffer.isEmpty) return;
    runs.add(TextRun(buffer.toString(), isEmoji: bufferIsEmoji!));
    buffer.clear();
  }

  var i = 0;
  while (i < cps.length) {
    final end = _clusterEnd(cps, i);
    final isEmoji = end > i;
    if (bufferIsEmoji != null && bufferIsEmoji != isEmoji) flush();
    bufferIsEmoji = isEmoji;
    buffer.write(String.fromCharCodes(cps.sublist(i, isEmoji ? end : i + 1)));
    i = isEmoji ? end : i + 1;
  }
  flush();
  return runs;
}

/// End (exclusive) of the emoji cluster starting at [start], or [start] itself
/// when no emoji begins there. Absorbs ZWJ sequences so 👨‍👩‍👧 stays one run —
/// splitting it would break the ligature into three separate people.
int _clusterEnd(List<int> cps, int start) {
  var i = _unitEnd(cps, start);
  if (i == start) return start;
  while (i + 1 < cps.length && cps[i] == _zwj) {
    final next = _unitEnd(cps, i + 1);
    if (next == i + 1) break; // dangling ZWJ — leave it to the text run
    i = next;
  }
  return i;
}

/// One emoji plus its trailing modifiers (variation selector, skin tone,
/// keycap, flag tags), or [start] when nothing emoji-like begins there.
int _unitEnd(List<int> cps, int start) {
  final cp = cps[start];
  final next = start + 1 < cps.length ? cps[start + 1] : null;

  int i;
  if (_isEmojiBase(cp)) {
    if (next == _vs15) return start; // caller wants the text glyph
    i = start + 1;
  } else if (_needsEmojiRequest(cp) && (next == _vs16 || next == _keycap)) {
    i = start + 1;
  } else {
    return start;
  }

  while (i < cps.length && _isModifier(cps[i])) {
    i++;
  }
  return i;
}

bool _isModifier(int cp) =>
    cp == _vs16 ||
    cp == _keycap ||
    (cp >= 0x1F3FB && cp <= 0x1F3FF) || // skin tones
    (cp >= 0xE0020 && cp <= 0xE007F); // flag tag characters

/// Codepoints that are emoji on their own.
bool _isEmojiBase(int cp) =>
    (cp >= 0x1F000 && cp <= 0x1FAFF) || // the emoji planes proper
    (cp >= 0x2600 && cp <= 0x27BF) || // misc symbols + dingbats (☀ ✅ ❤)
    (cp >= 0x2194 && cp <= 0x2199) ||
    cp == 0x21A9 ||
    cp == 0x21AA ||
    (cp >= 0x231A && cp <= 0x231B) ||
    cp == 0x2328 ||
    cp == 0x23CF ||
    (cp >= 0x23E9 && cp <= 0x23FA) ||
    cp == 0x24C2 ||
    (cp >= 0x25AA && cp <= 0x25AB) ||
    cp == 0x25B6 ||
    cp == 0x25C0 ||
    (cp >= 0x25FB && cp <= 0x25FE) ||
    (cp >= 0x2B05 && cp <= 0x2B07) ||
    cp == 0x2B1B ||
    cp == 0x2B1C ||
    cp == 0x2B50 ||
    cp == 0x2B55 ||
    cp == 0x2934 ||
    cp == 0x2935 ||
    cp == 0x3030 ||
    cp == 0x303D ||
    cp == 0x3297 ||
    cp == 0x3299;

/// Codepoints that are ordinary text unless emoji presentation is asked for.
/// © and ™ in prose, and digits, must keep the text font.
bool _needsEmojiRequest(int cp) =>
    cp == 0xA9 ||
    cp == 0xAE ||
    cp == 0x2122 ||
    cp == 0x2139 ||
    cp == 0x203C ||
    cp == 0x2049 ||
    cp == 0x23 || // #️⃣
    cp == 0x2A || // *️⃣
    (cp >= 0x30 && cp <= 0x39); // 0️⃣–9️⃣
