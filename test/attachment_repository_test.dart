import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chunked_layout.dart';
import 'package:rift/data/repositories/attachment_repository.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// Opening a downloaded blob: decrypted when it was sealed, checked against
/// its digest when it was sent unencrypted. A file the server changed must
/// not open either way.
void main() {
  final repo = AttachmentRepository();
  final data = Uint8List.fromList(List<int>.generate(4096, (i) => i * 7));

  test('a sealed blob opens with its key', () async {
    final blob = await repo.seal(data);
    final clear = await repo.open(
      ciphertext: blob.ciphertext,
      keyB64: blob.keyB64,
      nonceB64: blob.nonceB64,
    );
    expect(clear, data);
  });

  test('a plain file opens when it matches its digest', () async {
    final digest = await repo.digest(data);
    final opened = await repo.open(
      ciphertext: data,
      keyB64: '',
      nonceB64: '',
      sha256B64: digest,
    );
    expect(opened, data);
  });

  test('a plain file the server changed does not open', () async {
    final digest = await repo.digest(data);
    final changed = Uint8List.fromList(data)..[100] ^= 1;
    await expectLater(
      repo.open(
        ciphertext: changed,
        keyB64: '',
        nonceB64: '',
        sha256B64: digest,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  // A file sealed a chunk at a time, opened whole from memory — the road for
  // one small enough to draw. The upload and the ranged download are driven
  // against the local stack instead (TESTING.md).
  group('a chunked blob', () {
    final crypto = CryptoRepository();
    final key = crypto.generateFileKey();
    final prefix = crypto.generateChunkNoncePrefix();
    const chunk = 1000;
    final file = Uint8List.fromList(List<int>.generate(2500, (i) => i * 3));

    Future<List<Uint8List>> sealed() async {
      final layout = ChunkedLayout(plainSize: file.length, chunkSize: chunk);
      return [
        for (var i = 0; i < layout.chunkCount; i++)
          await crypto.sealChunk(
            data: Uint8List.sublistView(
              file,
              layout.plainOffset(i),
              layout.plainOffset(i) + layout.plainLength(i),
            ),
            key: key,
            noncePrefix: prefix,
            index: i,
            last: layout.isLast(i),
          ),
      ];
    }

    Future<Uint8List> open(List<Uint8List> chunks) => repo.open(
      ciphertext: Uint8List.fromList(chunks.expand((c) => c).toList()),
      keyB64: CryptoRepository.toBase64(key),
      nonceB64: CryptoRepository.toBase64(prefix),
      chunkSize: chunk,
    );

    test('opens', () async {
      expect(await open(await sealed()), file);
    });

    test('with two chunks swapped, does not', () async {
      final c = await sealed();
      await expectLater(open([c[1], c[0], c[2]]), throwsA(anything));
    });

    test('cut off after a whole chunk, does not', () async {
      final c = await sealed();
      await expectLater(open(c.sublist(0, 2)), throwsA(anything));
    });
  });

  // FIPS 180-2's "abc", which rust/src/blob_cipher.rs checks the native
  // digest against: the two must agree for a plain file to open everywhere.
  test('the digest is SHA-256', () async {
    expect(
      await repo.digest(Uint8List.fromList('abc'.codeUnits)),
      'ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=',
    );
  });
}
