import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM over a whole blob: an attachment or a saved conversation.
///
/// Its own seam because the bytes can be large and where the work runs is
/// the whole difference. [DartBlobCipher] is the reference and what the web
/// uses (the browser hands it to WebCrypto); the app installs one backed by
/// its Rust library everywhere else, through [CryptoRepository.blobCipher].
/// Every implementation writes the same bytes: the ciphertext with its 16-byte
/// tag appended, under the 12-byte [nonce] the caller chose.
abstract interface class BlobCipher {
  Future<Uint8List> seal({
    required Uint8List data,
    required Uint8List key,
    required Uint8List nonce,
  });

  /// Throws when the tag does not match: a wrong key, or changed bytes.
  Future<Uint8List> open({
    required Uint8List sealed,
    required Uint8List key,
    required Uint8List nonce,
  });
}

/// [BlobCipher] in Dart, with the `cryptography` package.
///
/// On a desktop or phone this runs on the calling isolate, about 4 s for
/// 50 MB with the window frozen throughout, which is why the app replaces it.
class DartBlobCipher implements BlobCipher {
  const DartBlobCipher();

  @override
  Future<Uint8List> seal({
    required Uint8List data,
    required Uint8List key,
    required Uint8List nonce,
  }) async {
    final box = await AesGcm.with256bits().encrypt(
      data,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    return Uint8List.fromList(box.concatenation(nonce: false));
  }

  @override
  Future<Uint8List> open({
    required Uint8List sealed,
    required Uint8List key,
    required Uint8List nonce,
  }) async {
    final algorithm = AesGcm.with256bits();
    final macLength = algorithm.macAlgorithm.macLength;
    final box = SecretBox(
      sealed.sublist(0, sealed.length - macLength),
      nonce: nonce,
      mac: Mac(sealed.sublist(sealed.length - macLength)),
    );
    final clear = await algorithm.decrypt(box, secretKey: SecretKey(key));
    return Uint8List.fromList(clear);
  }
}
