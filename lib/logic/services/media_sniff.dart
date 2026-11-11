import 'dart:typed_data';

/// What an MP4-family file (mp4, m4a, mov, 3gp) holds, read from its box
/// tree: whether it has a video track, the picture's size as shown (a phone's
/// portrait video is stored on its side with a turn to apply, so its size
/// comes out turned), and its length. Null when [bytes], a whole file, is not
/// one of those or is cut short before its track list.
///
/// A file's label is the sender's guess — a picker's MIME type or its
/// extension — and phones label a short MP4 video `audio/mp4` often enough
/// that one arrived drawn as a voice note. Played as audio it opened a video
/// window of the system player's own (GStreamer's on Linux), so what a file
/// holds is read from the file before it is treated as sound or as video.
///
/// Reads the box tree only (`moov` → `trak` → `tkhd`, `mdia` → `hdlr`), never
/// the media, so it costs nothing next to the download.
IsoMediaInfo? isoMediaInfo(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  // Every MP4-family file opens with its `ftyp` box.
  final first = _box(data, 0, bytes.length);
  if (first == null || first.type != 'ftyp') return null;
  final moov = _find(data, 0, bytes.length, 'moov');
  if (moov == null) return null;
  final mvhd = _find(data, moov.body, moov.end, 'mvhd');
  final durationMs = mvhd == null ? null : _durationMs(data, mvhd);
  for (final trak in _children(data, moov.body, moov.end, 'trak')) {
    final mdia = _find(data, trak.body, trak.end, 'mdia');
    if (mdia == null) continue;
    final hdlr = _find(data, mdia.body, mdia.end, 'hdlr');
    // version and flags (4), pre_defined (4), then the handler type.
    if (hdlr == null || hdlr.body + 12 > hdlr.end) continue;
    if (_type(data, hdlr.body + 8) != 'vide') continue;
    final tkhd = _find(data, trak.body, trak.end, 'tkhd');
    final size = tkhd == null ? null : _shownSize(data, tkhd);
    return (
      hasVideo: true,
      width: size?.width,
      height: size?.height,
      durationMs: durationMs,
    );
  }
  return (hasVideo: false, width: null, height: null, durationMs: durationMs);
}

typedef IsoMediaInfo = ({
  bool hasVideo,
  int? width,
  int? height,
  int? durationMs,
});

/// Whether [bytes] is an MP4-family file with a video track in it: true or
/// false, or null when it is not one of those ([isoMediaInfo]).
bool? isoMediaHasVideo(Uint8List bytes) => isoMediaInfo(bytes)?.hasVideo;

/// The movie's length from its `mvhd`: its duration over its timescale.
/// Null when it says none, as a fragmented file's does.
int? _durationMs(ByteData data, _Box mvhd) {
  final version = data.getUint8(mvhd.body);
  // version 1: 64-bit times; version 0: 32-bit.
  final scaleAt = mvhd.body + (version == 1 ? 20 : 12);
  final durationEnd = scaleAt + (version == 1 ? 12 : 8);
  if (durationEnd > mvhd.end) return null;
  final scale = data.getUint32(scaleAt);
  final duration = version == 1
      ? data.getUint64(scaleAt + 4)
      : data.getUint32(scaleAt + 4);
  if (scale == 0 || duration == 0 || duration == 0xffffffff) return null;
  return duration * 1000 ~/ scale;
}

/// The track's size from its `tkhd`, turned by its matrix when that turns it
/// a quarter: a phone stores a portrait video on its side.
({int width, int height})? _shownSize(ByteData data, _Box tkhd) {
  final version = data.getUint8(tkhd.body);
  final matrixAt = tkhd.body + (version == 1 ? 52 : 40);
  final sizeAt = matrixAt + 36;
  if (sizeAt + 8 > tkhd.end) return null;
  // 16.16 fixed point.
  final width = data.getUint32(sizeAt) >> 16;
  final height = data.getUint32(sizeAt + 4) >> 16;
  if (width == 0 || height == 0) return null;
  // The matrix's a and d are zero when it turns the picture a quarter.
  final a = data.getInt32(matrixAt);
  final d = data.getInt32(matrixAt + 16);
  final turned = a == 0 && d == 0;
  return turned
      ? (width: height, height: width)
      : (width: width, height: height);
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
