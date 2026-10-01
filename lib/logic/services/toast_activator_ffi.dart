import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Tells Windows which program handles presses on Rift's notifications, for
/// the current user: `HKCU\Software\Classes\CLSID\{guid}\LocalServer32`.
///
/// flutter_local_notifications registers the class only inside the running
/// process (`CoRegisterClassObject`) and names it under the AUMID as its
/// `CustomActivator`, but never writes this key. Without it Windows does not
/// deliver a press at all, even to a Rift that is running — the class was
/// reachable through COM, and pressing still did nothing until this key
/// existed. It is what Microsoft's recipe for unpackaged apps, and the Windows
/// App SDK, write. Rewritten at every start, so it follows the executable if
/// it moves. Windows only; throws [WindowsException] if the write fails.
void registerToastActivator(String guid, String command) => using((alloc) {
  final data = command.toNativeUtf16(allocator: alloc);
  final result = RegSetKeyValue(
    HKEY_CURRENT_USER,
    alloc.pcwstr('Software\\Classes\\CLSID\\{$guid}\\LocalServer32'),
    null,
    REG_SZ,
    data,
    (command.length + 1) * sizeOf<Uint16>(),
  );
  if (result != ERROR_SUCCESS) {
    throw WindowsException(result.toHRESULT());
  }
});
