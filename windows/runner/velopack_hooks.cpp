#include "velopack_hooks.h"

#include <windows.h>

#include <shellapi.h>
#include <shobjidl.h>

#include <string>
#include <vector>

namespace {

// The old installer's app id (inno_bundle's `id` in pubspec.yaml, before
// Rift moved to Velopack), which is also the toast activator's class
// (ToastIdentity). Every profile's class shares its first 24 characters.
constexpr wchar_t kLegacyAppId[] = L"919df387-f79b-5d74-bee3-b08f176b2a14";
constexpr size_t kClassPrefixLength = 24;

constexpr wchar_t kAppUserModelId[] = L"CodingFries.Rift";

// Where a refused prompt is remembered, so it is asked once.
constexpr wchar_t kSettingsKey[] = L"Software\\CodingFries\\Rift";
constexpr wchar_t kKeepLegacyValue[] = L"KeepOldInstall";

std::vector<std::wstring> Arguments() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  std::vector<std::wstring> args;
  for (int i = 1; argv != nullptr && i < argc; i++) args.emplace_back(argv[i]);
  ::LocalFree(argv);
  return args;
}

std::wstring ExecutableDirectory() {
  wchar_t path[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) return L"";
  std::wstring dir(path, length);
  return dir.substr(0, dir.find_last_of(L'\\'));
}

// Velopack puts the app in `<root>\current`, beside its `Update.exe`.
bool InstalledByVelopack() {
  const std::wstring dir = ExecutableDirectory();
  const size_t slash = dir.find_last_of(L'\\');
  if (slash == std::wstring::npos) return false;
  if (::_wcsicmp(dir.c_str() + slash + 1, L"current") != 0) return false;
  const std::wstring update = dir.substr(0, slash) + L"\\Update.exe";
  return ::GetFileAttributesW(update.c_str()) != INVALID_FILE_ATTRIBUTES;
}

bool StartsWith(const std::wstring& name, const std::wstring& prefix) {
  return name.size() >= prefix.size() &&
         ::_wcsnicmp(name.c_str(), prefix.c_str(), prefix.size()) == 0;
}

// `base` itself, or a profile's `base.<profile>`.
bool IsNameOrProfile(const std::wstring& name, const std::wstring& base) {
  return ::_wcsicmp(name.c_str(), base.c_str()) == 0 ||
         StartsWith(name, base + L".");
}

template <typename Match>
void DeleteSubkeys(const wchar_t* parent, Match match) {
  HKEY key;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, parent, 0,
                      KEY_ENUMERATE_SUB_KEYS | DELETE, &key) != ERROR_SUCCESS) {
    return;
  }
  std::vector<std::wstring> doomed;
  wchar_t name[256];
  for (DWORD i = 0;; i++) {
    DWORD length = 256;
    if (::RegEnumKeyExW(key, i, name, &length, nullptr, nullptr, nullptr,
                        nullptr) != ERROR_SUCCESS) {
      break;
    }
    if (match(std::wstring(name, length))) doomed.emplace_back(name, length);
  }
  for (const auto& subkey : doomed) ::RegDeleteTreeW(key, subkey.c_str());
  ::RegCloseKey(key);
}

// The registry keys Rift writes for the person, as the old installer's
// uninstall_cleanup.iss removed them:
// - Software\Classes\CLSID\{<app id's first groups>...}: the class a press on
//   a notification is delivered to (registerToastActivator), one per profile.
// - Software\Classes\rift: the rift:// scheme (registerInviteScheme).
// - Software\Classes\AppUserModelId\CodingFries.Rift[.<profile>] and the
//   push notification backup of the same name, which
//   flutter_local_notifications writes when it registers the app.
// Windows' own notification settings for the app are Windows', and stay.
void RemoveRegistryKeys() {
  const std::wstring class_prefix =
      L"{" + std::wstring(kLegacyAppId, kClassPrefixLength);
  DeleteSubkeys(L"Software\\Classes\\CLSID", [&](const std::wstring& name) {
    return StartsWith(name, class_prefix);
  });
  ::RegDeleteTreeW(HKEY_CURRENT_USER, L"Software\\Classes\\rift");
  for (const wchar_t* parent :
       {L"Software\\Classes\\AppUserModelId",
        L"Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications\\"
        L"Backup"}) {
    DeleteSubkeys(parent, [](const std::wstring& name) {
      return IsNameOrProfile(name, kAppUserModelId);
    });
  }
  ::RegDeleteTreeW(HKEY_CURRENT_USER, kSettingsKey);
}

// The old installer's uninstaller, if that copy is still installed. Inno
// Setup names its key after the app id, with `_is1` on the end; it writes it
// to the 64-bit view, and the 32-bit one is read in case.
std::wstring LegacyUninstaller() {
  const std::wstring key = std::wstring(
      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\") +
      kLegacyAppId + L"_is1";
  for (const REGSAM view : {KEY_WOW64_64KEY, KEY_WOW64_32KEY}) {
    wchar_t value[MAX_PATH * 2];
    DWORD size = sizeof(value);
    if (::RegGetValueW(HKEY_LOCAL_MACHINE, key.c_str(), L"UninstallString",
                       RRF_RT_REG_SZ | (view == KEY_WOW64_64KEY
                                            ? RRF_SUBKEY_WOW6464KEY
                                            : RRF_SUBKEY_WOW6432KEY),
                       nullptr, value, &size) == ERROR_SUCCESS) {
      std::wstring path(value);
      // Stored quoted.
      if (path.size() >= 2 && path.front() == L'"') {
        path = path.substr(1, path.find(L'"', 1) - 1);
      }
      return path;
    }
  }
  return L"";
}

bool LegacyRemovalRefused() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  return ::RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, kKeepLegacyValue,
                        RRF_RT_REG_DWORD, nullptr, &value,
                        &size) == ERROR_SUCCESS &&
         value != 0;
}

void RememberLegacyRemovalRefused() {
  const DWORD one = 1;
  ::RegSetKeyValueW(HKEY_CURRENT_USER, kSettingsKey, kKeepLegacyValue,
                    REG_DWORD, &one, sizeof(one));
}

}  // namespace

bool HandleVelopackHook() {
  const std::vector<std::wstring> args = Arguments();
  if (args.empty() || !StartsWith(args[0], L"--veloapp-")) return false;
  // Install and update need nothing here: every start registers what Rift
  // needs (the rift:// scheme, the notification identity) for wherever it
  // now lives, and Velopack starts Rift once it is done.
  if (::_wcsicmp(args[0].c_str(), L"--veloapp-uninstall") == 0) {
    RemoveRegistryKeys();
  }
  return true;
}

void RemoveLegacyInstall() {
  if (!InstalledByVelopack()) return;
  // A profile is a second identity on the same machine (StorageNamespace),
  // and only the person's own one should be asking for the administrator.
  wchar_t profile[2];
  if (::GetEnvironmentVariableW(L"RIFT_PROFILE", profile, 2) > 0) return;
  if (LegacyRemovalRefused()) return;
  const std::wstring uninstaller = LegacyUninstaller();
  if (uninstaller.empty()) return;

  SHELLEXECUTEINFOW info = {sizeof(info)};
  info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
  info.lpVerb = L"runas";
  info.lpFile = uninstaller.c_str();
  info.lpParameters = L"/VERYSILENT /SUPPRESSMSGBOXES /NORESTART";
  info.nShow = SW_HIDE;
  if (!::ShellExecuteExW(&info)) {
    if (::GetLastError() == ERROR_CANCELLED) RememberLegacyRemovalRefused();
    return;
  }
  // The old uninstaller also removes the keys above, so it must be done
  // before this start registers them again.
  if (info.hProcess != nullptr) {
    ::WaitForSingleObject(info.hProcess, 120000);
    ::CloseHandle(info.hProcess);
  }
}

void ApplyInstalledAppUserModelId() {
  if (InstalledByVelopack()) {
    ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);
  }
}
