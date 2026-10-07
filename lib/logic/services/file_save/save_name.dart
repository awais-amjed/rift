/// [chosen], with [suggested]'s extension put back when the name chosen has
/// none.
///
/// Windows' save dialog hides the extension of the name it is given, and with
/// no file types to go on it does not add it back: a file offered as
/// `movie.bin` was saved as `movie`, which nothing on the machine would open.
/// Seen Oct 7 in a Windows 11 VM. A name typed with an extension of its own
/// is kept as it is.
///
/// The suggested name is the sender's, so only an extension that is letters
/// and digits is put back: anything else (a slash, a colon naming a Windows
/// data stream) would make the path something the person did not pick.
String keepExtension(String chosen, String suggested) {
  final extension = RegExp(r'\.[A-Za-z0-9]{1,16}$').firstMatch(suggested);
  if (extension == null || extension.start == 0) return chosen;
  final name = chosen.substring(chosen.lastIndexOf(RegExp(r'[\\/]')) + 1);
  if (name.lastIndexOf('.') > 0) return chosen;
  return '$chosen${extension.group(0)}';
}
