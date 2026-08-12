/// Bytes as a short human string — `840 B`, `12 KB`, `2.3 MB`.
///
/// One definition, because size text now appears in three unrelated places: a
/// file card in the message list, the composer refusing an oversized file, and
/// the server settings dialog describing a cap. Two of those are widgets and
/// one is logic, so it lives here where all three can reach it.
String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
