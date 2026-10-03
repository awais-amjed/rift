; Removes, at uninstall, the registry keys Rift writes for the current user.
;
; inno_bundle has no option for this, so scripts/build_windows_installer.ps1
; includes this file in the script inno_bundle generates. Keep it ASCII.
;
; - Software\Classes\CLSID\{<AppId with its last group changed>}: the class a
;   press on a notification is delivered to (registerToastActivator in
;   lib/logic/services/toast_activator_ffi.dart). Every storage namespace's
;   class shares the AppId's first four groups (ToastIdentity), so they are
;   matched on those.
; - Software\Classes\rift: the rift:// scheme invite pages open the app with
;   (registerInviteScheme in lib/logic/services/invite_scheme_ffi.dart).
; - Software\Classes\AppUserModelId\CodingFries.Rift[.<profile>] and
;   ...\PushNotifications\Backup\CodingFries.Rift[.<profile>]: written by
;   flutter_local_notifications when it registers the app.
;
; The uninstaller runs elevated, so HKCU is the account that approved the
; prompt - the person themselves, unless someone else's admin credentials
; were typed in. Windows' own notification settings for the app
; (Notifications\Settings) are Windows', and left alone.

[Code]
function RiftNameMatches(const Name, Base: String): Boolean;
begin
  Result := (CompareText(Name, Base) = 0) or
    (CompareText(Copy(Name, 1, Length(Base) + 1), Base + '.') = 0);
end;

procedure RiftDeleteSubkeys(const Parent, Base: String; ByPrefix: Boolean);
var
  Names: TArrayOfString;
  I: Integer;
  Hit: Boolean;
begin
  if not RegGetSubkeyNames(HKCU, Parent, Names) then Exit;
  for I := 0 to GetArrayLength(Names) - 1 do
  begin
    if ByPrefix then
      Hit := CompareText(Copy(Names[I], 1, Length(Base)), Base) = 0
    else
      Hit := RiftNameMatches(Names[I], Base);
    if Hit then
      RegDeleteKeyIncludingSubkeys(HKCU, Parent + '\' + Names[I]);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  RiftDeleteSubkeys('Software\Classes\CLSID',
    '{' + Copy('{#SetupSetting("AppId")}', 1, 24), True);
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\rift');
  RiftDeleteSubkeys('Software\Classes\AppUserModelId',
    'CodingFries.Rift', False);
  RiftDeleteSubkeys(
    'Software\Microsoft\Windows\CurrentVersion\PushNotifications\Backup',
    'CodingFries.Rift', False);
end;
