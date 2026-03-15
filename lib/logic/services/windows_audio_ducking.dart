// On web dart:io is unavailable, so export the no-op stub.
// On all native platforms export the real win32_registry implementation.
export 'windows_audio_ducking_stub.dart'
    if (dart.library.io) 'windows_audio_ducking_native.dart';
