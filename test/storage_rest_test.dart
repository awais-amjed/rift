import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rift/data/repositories/storage_rest.dart';

/// The Storage REST rules the attachment, avatar and soundboard repositories
/// share.
void main() {
  http.Response reply(int code) => http.Response('', code);

  group('refusal', () {
    test('an expired or refused token is token_expired', () {
      // The code ServerCubit re-authenticates on; anything else would turn an
      // expired session into a failed upload.
      for (final code in [401, 403]) {
        final r = StorageRest.refusal(reply(code), failed: 'Upload failed');
        expect(r!.success, isFalse);
        expect(r.errorCode, 'token_expired');
      }
    });

    test('any other failure names the operation and the status', () {
      final r = StorageRest.refusal(reply(500), failed: 'Upload failed');
      expect(r!.error, 'Upload failed (500)');
      expect(r.errorCode, isNull);
    });

    test('a success is not a refusal', () {
      expect(StorageRest.refusal(reply(200), failed: 'x'), isNull);
      expect(StorageRest.refusal(reply(204), failed: 'x'), isNull);
    });
  });

  group('freshPath', () {
    test('is the folder, random hex, then the extension', () {
      final path = StorageRest.freshPath('user-1', extension: 'img');
      expect(path, matches(RegExp(r'^user-1/[0-9a-f]{24}\.img$')));
    });

    test('never repeats', () {
      final paths = {
        for (var i = 0; i < 200; i++)
          StorageRest.freshPath('s', extension: 'bin', bytes: 16),
      };
      expect(paths, hasLength(200));
    });
  });
}
