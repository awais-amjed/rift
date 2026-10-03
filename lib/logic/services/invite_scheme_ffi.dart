import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Tells Windows that `rift://` links open this program, for the current
/// user: `HKCU\Software\Classes\rift`.
///
/// The invite page's "Open in Rift" is a `rift://join#…` link, and a browser
/// hands it to whatever is registered here. app_links reads the link from the
/// command line but registers nothing, so without this the button did nothing
/// at all on Windows (found Oct 4 2026). Rewritten at every start, so it
/// follows the executable if it moves; the installer removes it again
/// (`windows/installer/uninstall_cleanup.iss`). Windows only; throws
/// [WindowsException] if a write fails.
///
/// The command passes the link as the only argument: app_links takes it from
/// there only when there is exactly one.
void registerInviteScheme(String executable) => using((alloc) {
  void set(String key, String? name, String value) {
    final data = value.toNativeUtf16(allocator: alloc);
    final result = RegSetKeyValue(
      HKEY_CURRENT_USER,
      alloc.pcwstr('Software\\Classes\\rift$key'),
      name == null ? null : alloc.pcwstr(name),
      REG_SZ,
      data,
      (value.length + 1) * sizeOf<Uint16>(),
    );
    if (result != ERROR_SUCCESS) {
      throw WindowsException(result.toHRESULT());
    }
  }

  set('', null, 'URL:Rift');
  set('', 'URL Protocol', '');
  set('\\shell\\open\\command', null, '"$executable" "%1"');
});
