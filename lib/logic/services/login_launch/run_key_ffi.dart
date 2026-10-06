import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// What Windows starts when the person signs in, for the current user.
const _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';

/// Has Windows run [command] at sign-in, under [name]. Windows only; throws
/// [WindowsException] if the write fails.
void setRunValue(String name, String command) => using((alloc) {
  final data = command.toNativeUtf16(allocator: alloc);
  final result = RegSetKeyValue(
    HKEY_CURRENT_USER,
    alloc.pcwstr(_runKey),
    alloc.pcwstr(name),
    REG_SZ,
    data,
    (command.length + 1) * sizeOf<Uint16>(),
  );
  if (result != ERROR_SUCCESS) throw WindowsException(result.toHRESULT());
});

/// Removes [name] from what Windows runs at sign-in. Already gone is fine.
void deleteRunValue(String name) => using((alloc) {
  final result = RegDeleteKeyValue(
    HKEY_CURRENT_USER,
    alloc.pcwstr(_runKey),
    alloc.pcwstr(name),
  );
  if (result != ERROR_SUCCESS && result != ERROR_FILE_NOT_FOUND) {
    throw WindowsException(result.toHRESULT());
  }
});
