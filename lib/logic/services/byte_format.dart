/// Bytes as a short human string — `840 B`, `12 KB`, `2.3 MB`, `5 MB`.
///
/// One definition, because size text now appears in three unrelated places: a
/// file card in the message list, the composer refusing an oversized file, and
/// the server settings dialog describing a cap. Two of those are widgets and
/// one is logic, so it lives here where all three can reach it.
///
/// A whole number of megabytes drops its decimal. A cap is nearly always a
/// round figure, and "Up to 5.0 MB" reads as a measurement of something
/// rather than as the rule it is.
String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${_trim(bytes / (1024 * 1024))} MB';
}

/// One decimal place, unless it is a zero.
String _trim(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
