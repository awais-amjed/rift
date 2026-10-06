/// [setRunValue] and [deleteRunValue], behind a conditional export: the real
/// ones reach `dart:ffi`, which the web build cannot compile.
library;

export 'run_key_stub.dart' if (dart.library.ffi) 'run_key_ffi.dart';
