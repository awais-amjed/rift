// tray_manager is FFI since 0.7, and dart:ffi fails the whole web compile
// rather than failing at runtime, so the web gets a stub with no icon.
export 'tray_service_stub.dart'
    if (dart.library.ffi) 'tray_service_native.dart';
