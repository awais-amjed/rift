/// [NoiseFilter], behind a conditional export: the real one reaches
/// `dart:ffi`, which the web build cannot compile.
library;

export 'noise_filter_stub.dart' if (dart.library.ffi) 'noise_filter_ffi.dart';
