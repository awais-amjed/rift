import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'profile_secure_storage.dart';

/// Windows' Data Protection API for the current user: what
/// flutter_secure_storage seals its file with, called the same way, so a file
/// it wrote opens here. Windows only.
class DpapiCodec implements SecretCodec {
  const DpapiCodec();

  @override
  Uint8List seal(Uint8List plain) => _run(plain, protect: true);

  @override
  Uint8List open(Uint8List sealed) => _run(sealed, protect: false);

  static Uint8List _run(Uint8List input, {required bool protect}) =>
      using((alloc) {
        final data = alloc<Uint8>(input.length);
        data.asTypedList(input.length).setAll(0, input);
        final inBlob = alloc<CRYPT_INTEGER_BLOB>();
        inBlob.ref
          ..cbData = input.length
          ..pbData = data;
        final outBlob = alloc<CRYPT_INTEGER_BLOB>();
        final Win32Result(:value, :error) = protect
            ? CryptProtectData(inBlob, null, null, null, 0, outBlob)
            : CryptUnprotectData(inBlob, null, null, null, 0, outBlob);
        final out = outBlob.ref.pbData;
        if (!value || out.address == NULL) {
          throw FormatException(
            '${protect ? 'CryptProtectData' : 'CryptUnprotectData'} failed: '
            '${error.toHRESULT().toHexString()}',
          );
        }
        try {
          return Uint8List.fromList(out.asTypedList(outBlob.ref.cbData));
        } finally {
          LocalFree(HLOCAL(out.cast()));
        }
      });
}
