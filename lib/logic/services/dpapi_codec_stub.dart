import 'dart:typed_data';

import 'profile_secure_storage.dart';

/// The web's [DpapiCodec]: never constructed there, since only Windows uses
/// [ProfileSecureStorage].
class DpapiCodec implements SecretCodec {
  const DpapiCodec();

  @override
  Uint8List seal(Uint8List plain) => throw UnsupportedError('DPAPI');

  @override
  Uint8List open(Uint8List sealed) => throw UnsupportedError('DPAPI');
}
