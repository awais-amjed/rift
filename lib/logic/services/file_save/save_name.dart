/// [chosen], with [suggested]'s extension put back when the name chosen has
/// none.
///
/// Windows' save dialog hides the extension of the name it is given, and with
/// no file types to go on it does not add it back: a file offered as
/// `movie.bin` was saved as `movie`, which nothing on the machine would open.
/// Seen Oct 7 in a Windows 11 VM. A name typed with an extension of its own
/// is kept as it is.
String keepExtension(String chosen, String suggested) {
  final dot = suggested.lastIndexOf('.');
  if (dot <= 0 || dot == suggested.length - 1) return chosen;
  final name = chosen.substring(chosen.lastIndexOf(RegExp(r'[\\/]')) + 1);
  if (name.lastIndexOf('.') > 0) return chosen;
  return '$chosen${suggested.substring(dot)}';
}
