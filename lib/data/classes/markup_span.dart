/// The pieces a message body is drawn from.
///
/// Split from the parser in `logic/services/message_markup.dart` because both
/// the parser and the renderer that styles its output need these, and a type
/// two layers share belongs with the other models rather than inside one of
/// them.
library;

/// A formatting mark applied to a stretch of text.
enum Marker { bold, italic, strike, code }

/// One stretch of a message body that renders with a single set of marks.
class MarkupSpan {
  final String text;
  final Set<Marker> marks;

  /// The name in an `@name`, without the `@`, or null for ordinary text.
  ///
  /// Whether it is *really* a mention is not decided here: this says "somebody
  /// typed @foo", and the renderer, which knows the roster, decides whether to
  /// highlight it. Parsing cannot know, and guessing would mean styling
  /// `@nobody` as though it reached someone.
  final String? mention;

  const MarkupSpan(this.text, {this.marks = const {}, this.mention});

  bool get isCode => marks.contains(Marker.code);

  @override
  bool operator ==(Object other) =>
      other is MarkupSpan &&
      other.text == text &&
      other.mention == mention &&
      other.marks.length == marks.length &&
      other.marks.containsAll(marks);

  @override
  int get hashCode =>
      Object.hash(text, mention, Object.hashAllUnordered(marks));

  @override
  String toString() {
    final m = marks.isEmpty ? '' : ' ${marks.map((e) => e.name).join('+')}';
    return 'MarkupSpan($text$m${mention == null ? '' : ' @$mention'})';
  }
}
