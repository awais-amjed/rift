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

/// A track whose handler is [handler] ('soun', 'vide').
List<int> track(String handler) => box('trak', [
  ...box('tkhd', List.filled(20, 0)),
  ...box('mdia', [
    ...box('mdhd', List.filled(24, 0)),
    ...box('hdlr', [...List.filled(8, 0), ...handler.codeUnits, 0, 0, 0, 0]),
  ]),
]);

Uint8List file(List<List<int>> tracks, {bool moovLast = false}) {
  final ftyp = box('ftyp', [...'isom'.codeUnits, 0, 0, 2, 0]);
  final moov = box('moov', [
    ...box('mvhd', List.filled(12, 0)),
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
}
