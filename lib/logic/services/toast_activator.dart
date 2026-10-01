/// [registerToastActivator], behind a conditional export: the real one reaches
/// `dart:ffi`, which the web build cannot compile.
library;

export 'toast_activator_stub.dart'
    if (dart.library.ffi) 'toast_activator_ffi.dart';
