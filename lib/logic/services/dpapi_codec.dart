/// [DpapiCodec], behind a conditional export: the real one reaches `dart:ffi`,
/// which the web build cannot compile.
library;

export 'dpapi_codec_stub.dart' if (dart.library.ffi) 'dpapi_codec_ffi.dart';
