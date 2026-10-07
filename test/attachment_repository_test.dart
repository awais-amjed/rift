import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/repositories/attachment_repository.dart';

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

  // FIPS 180-2's "abc", which rust/src/blob_cipher.rs checks the native
  // digest against: the two must agree for a plain file to open everywhere.
  test('the digest is SHA-256', () async {
    expect(
      await repo.digest(Uint8List.fromList('abc'.codeUnits)),
      'ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=',
    );
  });
}
