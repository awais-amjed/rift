/// Reading what an admin typed into a limit field.
///
/// Limit fields are fiddlier than they look, because three different states all
/// have to be expressible in one small box:
///
///   * **blank** — for a channel, "inherit the server default"; for a form
///     field, "don't change this".
///   * **0** — an explicit "no limit", which is a real choice and not the same
///     as blank. A channel set to 0 opts *out* of a server-wide quota.
///   * **a number** — that many.
///
/// Every method here keeps those apart, and none of them throws: bad input
/// reads as [invalid] so a caller can say so rather than crash on a stray
/// letter.
class LimitInput {
  const LimitInput._();

  /// Bytes per megabyte, for the attachment cap — stored in bytes, typed in MB.
  static const int bytesPerMb = 1024 * 1024;

  /// Returned by [parse] when the text is neither blank nor a valid limit.
  static const int invalid = -1;

  /// True when the field has been left empty.
  static bool isBlank(String raw) => raw.trim().isEmpty;

  /// The limit [raw] describes: null when blank, [invalid] when it isn't a
  /// non-negative whole number, otherwise the number itself.
  static int? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null || value < 0) return invalid;
    return value;
  }

  /// The same, in megabytes, converted to the bytes the column stores. A cap
  /// of zero bytes would forbid every attachment, so 0 is rejected here rather
  /// than treated as "unlimited" — sizes have no "off".
  static int? parseMegabytes(String raw) {
    final mb = parse(raw);
    if (mb == null || mb == invalid || mb == 0) {
      return mb == null ? null : invalid;
    }
    return mb * bytesPerMb;
  }

  /// Bytes as a whole number of megabytes for display in a field, rounding up
  /// so a cap never renders as smaller than it is.
  static String megabytesOf(int bytes) =>
      ((bytes + bytesPerMb - 1) ~/ bytesPerMb).toString();

  /// How a stored limit reads back into a field: [unlimited] shows as blank so
  /// "no limit" and "nothing typed yet" look the same, which is what an admin
  /// means by leaving it empty.
  static String textOf(int value, {int unlimited = 0}) =>
      value == unlimited ? '' : value.toString();
}
