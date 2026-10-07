import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/file_save/save_name.dart';

void main() {
  group('keepExtension', () {
    test('puts back the extension Windows dropped', () {
      expect(
        keepExtension(r'C:\Users\a\Downloads\movie', 'movie.bin'),
        r'C:\Users\a\Downloads\movie.bin',
      );
    });

    test('puts it back on a name the person changed', () {
      expect(
        keepExtension(r'C:\Users\a\Downloads\clip', 'movie.mp4'),
        r'C:\Users\a\Downloads\clip.mp4',
      );
    });

    test('keeps an extension the person typed', () {
      expect(
        keepExtension(r'C:\Users\a\movie.txt', 'movie.bin'),
        r'C:\Users\a\movie.txt',
      );
      expect(
        keepExtension('/home/a/movie.bin', 'movie.bin'),
        '/home/a/movie.bin',
      );
    });

    test('a dot in a folder name is not an extension', () {
      expect(
        keepExtension(r'C:\Users\a.b\movie', 'movie.bin'),
        r'C:\Users\a.b\movie.bin',
      );
    });

    test('leaves the name alone when the file had no extension', () {
      expect(keepExtension(r'C:\a\README', 'README'), r'C:\a\README');
      expect(keepExtension(r'C:\a\.env', '.env'), r'C:\a\.env');
      expect(keepExtension(r'C:\a\notes', 'notes.'), r'C:\a\notes');
    });
  });
}
