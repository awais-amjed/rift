import 'dart:typed_data';

/// Whether [bytes], a whole file, is an MP4-family file (mp4, m4a, mov, 3gp)
/// with a video track in it: true or false, or null when it is not one of
/// those or is cut short before its track list.
///
/// A file's label is the sender's guess — a picker's MIME type or its
/// extension — and phones label a short MP4 video `audio/mp4` often enough
/// that one arrived drawn as a voice note. Played as audio it opened a video
/// window of the system player's own (GStreamer's on Linux), so what a file
/// holds is read from the file before it is treated as sound.
///
/// Reads the box tree only (`moov` → `trak` → `mdia` → `hdlr`), never the
/// media, so it costs nothing next to the download.
bool? isoMediaHasVideo(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  // Every MP4-family file opens with its `ftyp` box.
  final first = _box(data, 0, bytes.length);
  if (first == null || first.type != 'ftyp') return null;
  final moov = _find(data, 0, bytes.length, 'moov');
  if (moov == null) return null;
  for (final trak in _children(data, moov.body, moov.end, 'trak')) {
    final mdia = _find(data, trak.body, trak.end, 'mdia');
    if (mdia == null) continue;
    final hdlr = _find(data, mdia.body, mdia.end, 'hdlr');
    // version and flags (4), pre_defined (4), then the handler type.
    if (hdlr == null || hdlr.body + 12 > hdlr.end) continue;
    if (_type(data, hdlr.body + 8) == 'vide') return true;
  }
  return false;
}

typedef _Box = ({String type, int body, int end});

/// The box starting at [at], or null if it does not fit before [limit].
_Box? _box(ByteData data, int at, int limit) {
  if (at + 8 > limit) return null;
  var size = data.getUint32(at);
  var header = 8;
  if (size == 1) {
    // A 64-bit size follows the type.
    if (at + 16 > limit) return null;
    final large = data.getUint64(at + 8);
    if (large > limit - at) return null;
    size = large;
    header = 16;
  } else if (size == 0) {
    // Runs to the end of what contains it.
    size = limit - at;
  }
  if (size < header || at + size > limit) return null;
  return (type: _type(data, at + 4), body: at + header, end: at + size);
}

Iterable<_Box> _children(
  ByteData data,
  int from,
  int limit, [
  String? type,
]) sync* {
  var at = from;
  while (true) {
    final box = _box(data, at, limit);
    if (box == null) return;
    if (type == null || box.type == type) yield box;
    at = box.end;
  }
}

_Box? _find(ByteData data, int from, int limit, String type) {
  for (final box in _children(data, from, limit, type)) {
    return box;
  }
  return null;
}

String _type(ByteData data, int at) => String.fromCharCodes([
  data.getUint8(at),
  data.getUint8(at + 1),
  data.getUint8(at + 2),
  data.getUint8(at + 3),
]);
