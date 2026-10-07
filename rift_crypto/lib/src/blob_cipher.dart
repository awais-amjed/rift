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
///
/// [digest] rides along for an attachment sent unencrypted, which has no tag
/// and carries a SHA-256 in the sealed message instead.
///
/// A big file is sealed a chunk at a time ([sealChunk]), under STREAM: each
/// chunk is its own AES-GCM message, under a nonce made of a 7-byte prefix,
/// the chunk's position (4 bytes, big-endian) and a last-chunk flag (1 byte)
/// — see [chunkNonce]. That is what lets a file larger than memory be sealed
/// and opened, and what stops a server reordering, dropping or cutting off
/// chunks without a tag failing.
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

  /// SHA-256 of [data].
  Future<Uint8List> digest(Uint8List data);

  /// Encrypt chunk [index] of a file sealed under [key] and the 7-byte
  /// [noncePrefix]; [last] marks the final chunk. Returns it with its tag.
  Future<Uint8List> sealChunk({
    required Uint8List data,
    required Uint8List key,
    required Uint8List noncePrefix,
    required int index,
    required bool last,
  });

  /// Decrypt what [sealChunk] made. Throws when the chunk was changed, moved,
  /// or is not where the file ends when [last] says it is.
  Future<Uint8List> openChunk({
    required Uint8List sealed,
    required Uint8List key,
    required Uint8List noncePrefix,
    required int index,
    required bool last,
  });

  /// A SHA-256 to feed a piece at a time.
  BlobDigest startDigest();
}

/// SHA-256 over pieces given one after another, then [close]d once.
abstract interface class BlobDigest {
  Future<void> add(Uint8List data);
  Future<Uint8List> close();
}

/// The nonce of chunk [index] under STREAM: [prefix] (7 bytes), the index as
/// four big-endian bytes, and 1 for the last chunk or 0 for any other.
Uint8List chunkNonce(Uint8List prefix, int index, bool last) {
  if (prefix.length != 7) {
    throw ArgumentError.value(prefix.length, 'prefix', 'must be 7 bytes');
  }
  return Uint8List(12)
    ..setRange(0, 7, prefix)
    ..buffer.asByteData().setUint32(7, index)
    ..[11] = last ? 1 : 0;
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

  @override
  Future<Uint8List> digest(Uint8List data) async =>
      Uint8List.fromList((await Sha256().hash(data)).bytes);

  @override
  Future<Uint8List> sealChunk({
    required Uint8List data,
    required Uint8List key,
    required Uint8List noncePrefix,
    required int index,
    required bool last,
  }) => seal(data: data, key: key, nonce: chunkNonce(noncePrefix, index, last));

  @override
  Future<Uint8List> openChunk({
    required Uint8List sealed,
    required Uint8List key,
    required Uint8List noncePrefix,
    required int index,
    required bool last,
  }) => open(
    sealed: sealed,
    key: key,
    nonce: chunkNonce(noncePrefix, index, last),
  );

  @override
  BlobDigest startDigest() => _DartDigest();
}

class _DartDigest implements BlobDigest {
  final _sink = Sha256().newHashSink();

  @override
  Future<void> add(Uint8List data) async => _sink.add(data);

  @override
  Future<Uint8List> close() async {
    _sink.close();
    return Uint8List.fromList((await _sink.hash()).bytes);
  }
}
