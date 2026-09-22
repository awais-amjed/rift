import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/mime_util.dart';

/// The fallback for pickers that leave `XFile.mimeType` null.
void main() {
  test('reads the extension, whatever its case', () {
    expect(mimeFromName('photo.PNG'), 'image/png');
    expect(mimeFromName('a.b.jpeg'), 'image/jpeg');
    expect(mimeFromName('note.opus'), 'audio/opus');
  });

  test('no usable extension is generic binary', () {
    for (final name in ['README', 'trailing.', 'thing.xyz', '']) {
      expect(mimeFromName(name), 'application/octet-stream', reason: name);
    }
  });
}
