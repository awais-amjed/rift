import 'dart:typed_data';

import 'package:rift_crypto/rift_crypto.dart';

import '../../src/rust/api/blob_cipher.dart' as rust;

/// [BlobCipher] on the Rust library: the CPU's AES instructions, on one of
/// the bridge's worker threads instead of the UI isolate. The bytes are the
/// ones [DartBlobCipher] writes, so either opens what the other sealed.
///
/// Installed by `AppBootstrap` once the bridge is up; not on the web, which
/// has no bridge and whose Dart path already runs on WebCrypto.
class NativeBlobCipher implements BlobCipher {
  const NativeBlobCipher();

  @override
  Future<Uint8List> seal({
    required Uint8List data,
    required Uint8List key,
    required Uint8List nonce,
  }) => rust.sealBlob(key: key, nonce: nonce, data: data);

  @override
  Future<Uint8List> open({
    required Uint8List sealed,
    required Uint8List key,
    required Uint8List nonce,
  }) => rust.openBlob(key: key, nonce: nonce, sealed: sealed);

  @override
  Future<Uint8List> digest(Uint8List data) => rust.digestBlob(data: data);

  @override
  Future<Uint8List> sealChunk({
    required Uint8List data,
    required Uint8List key,
    required Uint8List noncePrefix,
    required int index,
    required bool last,
  }) => rust.sealBlobChunk(
    key: key,
    prefix: noncePrefix,
    position: index,
    last: last,
    data: data,
  );

  @override
  Future<Uint8List> openChunk({
    required Uint8List sealed,
    required Uint8List key,
    required Uint8List noncePrefix,
    required int index,
    required bool last,
  }) => rust.openBlobChunk(
    key: key,
    prefix: noncePrefix,
    position: index,
    last: last,
    sealed: sealed,
  );

  @override
  BlobDigest startDigest() => _NativeDigest(rust.BlobHasher());
}

class _NativeDigest implements BlobDigest {
  final rust.BlobHasher _hasher;
  _NativeDigest(this._hasher);

  @override
  Future<void> add(Uint8List data) => _hasher.update(data: data);

  @override
  Future<Uint8List> close() async {
    try {
      return await _hasher.finish();
    } finally {
      _hasher.dispose();
    }
  }
}
