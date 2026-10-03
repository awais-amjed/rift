; Registers the rift:// scheme at install, so "Open in Rift" works before
; Rift has been started once. The app writes the same key at every start
; (registerInviteScheme in lib/logic/services/invite_scheme_ffi.dart), which
; keeps it pointing at the right place after a move; uninstall_cleanup.iss
; removes it. Included by scripts/build_windows_installer.ps1. Keep it ASCII.
;
; The installer runs elevated, so HKCU is the account that approved the
; prompt - the person themselves, as for the cleanup.

[Registry]
Root: HKCU; Subkey: "Software\Classes\rift"; ValueType: string; ValueData: "URL:Rift"
Root: HKCU; Subkey: "Software\Classes\rift"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\rift\shell\open\command"; ValueType: string; ValueData: """{app}\rift.exe"" ""%1"""
