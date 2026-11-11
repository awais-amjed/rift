import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/media_sniff.dart';

/// One box: a 32-bit size, the type, then [body].
List<int> box(String type, List<int> body) {
  final size = 8 + body.length;
  return [
    (size >> 24) & 0xff,
    (size >> 16) & 0xff,
    (size >> 8) & 0xff,
    size & 0xff,
    ...type.codeUnits,
    ...body,
  ];
}

List<int> u32(int v) => [
  (v >> 24) & 0xff,
  (v >> 16) & 0xff,
  (v >> 8) & 0xff,
  v & 0xff,
];

/// A version 0 `tkhd`: the matrix turns a quarter when [turned], as a
/// phone's portrait video does.
List<int> tkhd(int width, int height, {bool turned = false}) => box('tkhd', [
  ...List.filled(40, 0),
  // a b u / c d v / x y w, a b c d in 16.16.
  ...u32(turned ? 0 : 0x10000), ...u32(turned ? 0x10000 : 0), ...u32(0),
  ...u32(turned ? 0xffff0000 : 0), ...u32(turned ? 0 : 0x10000), ...u32(0),
  ...u32(0), ...u32(0), ...u32(0x40000000),
  ...u32(width << 16), ...u32(height << 16),
]);

/// A track whose handler is [handler] ('soun', 'vide').
List<int> track(String handler, {List<int>? header}) => box('trak', [
  ...header ?? box('tkhd', List.filled(20, 0)),
  ...box('mdia', [
    ...box('mdhd', List.filled(24, 0)),
    ...box('hdlr', [...List.filled(8, 0), ...handler.codeUnits, 0, 0, 0, 0]),
  ]),
]);

Uint8List file(
  List<List<int>> tracks, {
  bool moovLast = false,
  List<int>? mvhd,
}) {
  final ftyp = box('ftyp', [...'isom'.codeUnits, 0, 0, 2, 0]);
  final moov = box('moov', [
    ...mvhd ?? box('mvhd', List.filled(12, 0)),
    for (final t in tracks) ...t,
  ]);
  final mdat = box('mdat', List.filled(64, 7));
  return Uint8List.fromList(
    moovLast ? [...ftyp, ...mdat, ...moov] : [...ftyp, ...moov, ...mdat],
  );
}

void main() {
  test('a video track is found, before or after the media', () {
    expect(isoMediaHasVideo(file([track('vide'), track('soun')])), isTrue);
    expect(
      isoMediaHasVideo(file([track('soun'), track('vide')], moovLast: true)),
      isTrue,
    );
  });

  test('sound alone is not a video', () {
    expect(isoMediaHasVideo(file([track('soun')])), isFalse);
  });

  test('something that is not MP4 is not judged', () {
    expect(isoMediaHasVideo(Uint8List.fromList('ID3\x04'.codeUnits)), isNull);
    expect(isoMediaHasVideo(Uint8List(0)), isNull);
  });

  test('a file cut before its track list is not judged', () {
    final whole = file([track('vide')], moovLast: true);
    expect(isoMediaHasVideo(Uint8List.sublistView(whole, 0, 60)), isNull);
  });

  test('a box claiming more than the file holds stops the walk', () {
    final bytes = file([track('vide')]);
    // Make the moov box claim far more than is there.
    bytes[16 + 0] = 0x7f;
    expect(isoMediaHasVideo(bytes), isNull);
  });

  test("a video's shown size and length are read", () {
    // version 0: times, then a 1000-a-second timescale and 4.5 s.
    final mvhd = box('mvhd', [
      ...List.filled(12, 0),
      ...u32(1000),
      ...u32(4500),
    ]);
    final info = isoMediaInfo(
      file([track('vide', header: tkhd(1440, 900))], mvhd: mvhd),
    );
    expect(info, (hasVideo: true, width: 1440, height: 900, durationMs: 4500));
  });

  test('a portrait phone video comes out upright', () {
    final info = isoMediaInfo(
      file([track('vide', header: tkhd(1920, 1080, turned: true))]),
    );
    expect(info?.width, 1080);
    expect(info?.height, 1920);
  });

  test('sound alone still has a length', () {
    final mvhd = box('mvhd', [
      ...List.filled(12, 0),
      ...u32(48000),
      ...u32(96000),
    ]);
    final info = isoMediaInfo(file([track('soun')], mvhd: mvhd));
    expect(info, (
      hasVideo: false,
      width: null,
      height: null,
      durationMs: 2000,
    ));
  });
}
