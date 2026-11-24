import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/soundboard_file_name.dart';

Uint8List _bytes(List<int> head) =>
    Uint8List.fromList([...head, ...List.filled(32, 0)]);

Uint8List _tagged(int offset, String tag) =>
    _bytes([...List.filled(offset, 0), ...tag.codeUnits]);

void main() {
  group('soundboardExtension', () {
    test('reads each format an upload may be from its first bytes', () {
      expect(soundboardExtension(_tagged(0, 'ID3')), 'mp3');
      // An MP3 with no tag starts on a frame: MPEG-1 layer III.
      expect(soundboardExtension(_bytes([0xFF, 0xFB, 0x90])), 'mp3');
      expect(soundboardExtension(_bytes([0xFF, 0xF1, 0x50])), 'aac');
      expect(soundboardExtension(_bytes([0xFF, 0xF9, 0x50])), 'aac');
      expect(soundboardExtension(_tagged(4, 'ftypM4A ')), 'm4a');
      expect(soundboardExtension(_tagged(0, 'OggS')), 'ogg');
      final wav = _tagged(0, 'RIFF');
      wav.setAll(8, 'WAVE'.codeUnits);
      expect(soundboardExtension(wav), 'wav');
    });

    test('a file that is none of them, or too short, has none', () {
      expect(soundboardExtension(_tagged(0, 'RIFF')), isNull, reason: 'AVI');
      expect(soundboardExtension(_bytes([0x89, 0x50, 0x4E, 0x47])), isNull);
      expect(soundboardExtension(Uint8List(0)), isNull);
      expect(soundboardExtension(Uint8List.fromList([0xFF])), isNull);
    });
  });

  group('soundboardFileName', () {
    test('is the name on the board with the extension of its bytes', () {
      expect(soundboardFileName('airhorn', _tagged(0, 'ID3')), 'airhorn.mp3');
      expect(
        soundboardFileName('sad trombone', _tagged(0, 'OggS')),
        'sad trombone.ogg',
      );
    });

    test('keeps out what a file name cannot hold', () {
      final mp3 = _tagged(0, 'ID3');
      expect(soundboardFileName('../../etc/passwd', mp3), '_.._etc_passwd.mp3');
      expect(
        soundboardFileName(r'a\b:c*d?"e"<f>|g', mp3),
        'a_b_c_d__e__f__g.mp3',
      );
      expect(soundboardFileName('  ...  ', mp3), 'clip.mp3');
      expect(soundboardFileName('end.', mp3), 'end.mp3');
    });

    test('an unknown format gets no extension rather than a guess', () {
      expect(soundboardFileName('beep', Uint8List(4)), 'beep');
    });
  });
}
