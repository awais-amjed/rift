#include "startup_guard.h"

#include <windows.h>

#include <tlhelp32.h>

#include <cwchar>
#include <filesystem>
#include <string>
#include <system_error>

#include "utils.h"

namespace {

// One per profile, beside the profiles' folders, under the root Dart keeps
// them in (StorageNamespace): %LOCALAPPDATA%\com.codingfries\rift.
std::filesystem::path MarkPath() {
  wchar_t base[MAX_PATH];
  const DWORD length =
      ::GetEnvironmentVariableW(L"LOCALAPPDATA", base, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return {};
  std::wstring name = L"starting";
  const std::wstring profile = RiftProfile();
  if (!profile.empty()) name += L"." + profile;
  // A profile is any string; a file name is not.
  for (auto& c : name) {
    if (std::wcschr(L"\\/:*?\"<>|", c) != nullptr) c = L'_';
  }
  return std::filesystem::path(base) / L"com.codingfries" / L"rift" / name;
}

bool RivaTunerRunning() {
  HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return false;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  bool found = false;
  for (BOOL more = ::Process32FirstW(snapshot, &entry); more && !found;
       more = ::Process32NextW(snapshot, &entry)) {
    found = ::_wcsicmp(entry.szExeFile, L"RTSS.exe") == 0;
  }
  ::CloseHandle(snapshot);
  return found;
}

// Names this program's own path, which RTSS's Add asks for.
void ExplainRivaTuner() {
  wchar_t exe[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
  const std::wstring path =
      length > 0 && length < MAX_PATH ? exe : L"RiftChat.exe";
  const std::wstring message =
      L"Rift closed while starting last time, and RivaTuner Statistics "
      L"Server is running.\n\n"
      L"RivaTuner (part of MSI Afterburner) hooks into apps to draw its "
      L"overlay, and after some Windows updates that hook makes them crash "
      L"as they open.\n\n"
      L"To fix it, close RivaTuner, or leave Rift out of it: in RivaTuner "
      L"press Add, choose\n\n" +
      path +
      L"\n\nand set Application detection level to None.\n\n"
      L"Press OK to start Rift.";
  // On top: Windows may refuse this process the foreground, and a message
  // that only flashes on the taskbar looks like Rift hanging.
  ::MessageBoxW(nullptr, message.c_str(), L"Rift",
                MB_OK | MB_ICONWARNING | MB_SETFOREGROUND | MB_TOPMOST);
}

}  // namespace

void CheckLastStartAndMark() {
  const std::filesystem::path mark = MarkPath();
  if (mark.empty()) return;
  std::error_code error;
  if (std::filesystem::exists(mark, error) && RivaTunerRunning()) {
    ExplainRivaTuner();
  }
  std::filesystem::create_directories(mark.parent_path(), error);
  HANDLE file = ::CreateFileW(mark.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) ::CloseHandle(file);
}

void MarkStartFinished() {
  const std::filesystem::path mark = MarkPath();
  if (mark.empty()) return;
  std::error_code error;
  std::filesystem::remove(mark, error);
}
