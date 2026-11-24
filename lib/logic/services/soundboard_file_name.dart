import 'dart:typed_data';

/// The name a soundboard clip is saved under: its name on the board, with
/// the extension its bytes say it is.
///
/// The server keeps every clip as `<random>.audio` and records no type, so
/// the format is read from the file itself — one of the five an upload may
/// be (`SoundboardStaging.extensions`). A file that is none of them is saved
/// with no extension rather than a guessed one.
///
/// The clip's name is whatever a member typed, so the characters a file name
/// cannot hold on Windows, and a path separator anywhere, become `_`.
String soundboardFileName(String name, Uint8List bytes) {
  var base = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '')
      .trim();
  if (base.isEmpty) base = 'clip';
  final extension = soundboardExtension(bytes);
  return extension == null ? base : '$base.$extension';
}

/// `mp3`, `m4a`, `aac`, `wav` or `ogg`, from the first bytes of a clip;
/// null for anything else.
String? soundboardExtension(Uint8List bytes) {
  bool at(int offset, String tag) {
    if (bytes.length < offset + tag.length) return false;
    for (var i = 0; i < tag.length; i++) {
      if (bytes[offset + i] != tag.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (at(0, 'RIFF') && at(8, 'WAVE')) return 'wav';
  if (at(0, 'OggS')) return 'ogg';
  if (at(4, 'ftyp')) return 'm4a';
  if (at(0, 'ID3')) return 'mp3';
  if (bytes.length >= 2 && bytes[0] == 0xFF) {
    // Both start with eleven set bits. ADTS (AAC) has layer 00, which no
    // MPEG audio frame has.
    if (bytes[1] & 0xF6 == 0xF0) return 'aac';
    if (bytes[1] & 0xE0 == 0xE0 && bytes[1] & 0x06 != 0) return 'mp3';
  }
  return null;
}
