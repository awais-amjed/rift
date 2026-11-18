#include "relaunch.h"

#include <windows.h>

#include <shellapi.h>

#include <cwchar>
#include <string>
#include <vector>

namespace {

// How long the copy before gets to leave on its own.
constexpr DWORD kLeaveMs = 10000;

bool StartsWith(const wchar_t* text, const wchar_t* prefix) {
  return ::wcsncmp(text, prefix, ::wcslen(prefix)) == 0;
}

// One argument as CommandLineToArgvW reads it back: quoted, with quotes and
// the backslashes before them escaped.
std::wstring Quoted(const std::wstring& argument) {
  std::wstring out = L"\"";
  size_t backslashes = 0;
  for (wchar_t c : argument) {
    if (c == L'\\') {
      backslashes++;
      continue;
    }
    if (c == L'"') {
      out.append(backslashes * 2 + 1, L'\\');
    } else {
      out.append(backslashes, L'\\');
    }
    backslashes = 0;
    out.push_back(c);
  }
  out.append(backslashes * 2, L'\\');
  out.push_back(L'"');
  return out;
}

// This start's arguments, less what said how and why it started: a link was
// already handled, and the window's state and the reason are said afresh.
std::vector<std::wstring> KeptArguments() {
  std::vector<std::wstring> kept;
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  for (int i = 1; argv != nullptr && i < argc; i++) {
    if (::wcscmp(argv[i], L"--minimized") == 0 ||
        ::wcscmp(argv[i], kAfterGpuResetFlag) == 0 ||
        StartsWith(argv[i], kAfterExitFlag) ||
        ::_wcsnicmp(argv[i], L"rift:", 5) == 0) {
      continue;
    }
    kept.push_back(argv[i]);
  }
  ::LocalFree(argv);
  return kept;
}

}  // namespace

bool RelaunchAfterExit(bool minimized) {
  wchar_t path[MAX_PATH * 4];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
  if (length == 0 || length >= ARRAYSIZE(path)) return false;

  // This process, as a handle the new copy inherits and may wait on or end.
  HANDLE self = nullptr;
  if (!::DuplicateHandle(::GetCurrentProcess(), ::GetCurrentProcess(),
                         ::GetCurrentProcess(), &self,
                         SYNCHRONIZE | PROCESS_TERMINATE |
                             PROCESS_QUERY_LIMITED_INFORMATION,
                         TRUE, 0)) {
    return false;
  }

  std::wstring command = Quoted(path);
  for (const std::wstring& argument : KeptArguments()) {
    command += L" " + Quoted(argument);
  }
  if (minimized) command += L" --minimized";
  command += L" ";
  command += kAfterGpuResetFlag;
  command += L" ";
  command += kAfterExitFlag;
  command += std::to_wstring(reinterpret_cast<uintptr_t>(self));

  // That handle alone is inherited, not every inheritable one this process
  // holds.
  SIZE_T size = 0;
  ::InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
  std::vector<char> list_memory(size);
  auto list =
      reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(list_memory.data());
  bool started = false;
  if (::InitializeProcThreadAttributeList(list, 1, 0, &size)) {
    if (::UpdateProcThreadAttribute(list, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                    &self, sizeof(self), nullptr, nullptr)) {
      STARTUPINFOEXW startup = {};
      startup.StartupInfo.cb = sizeof(startup);
      startup.lpAttributeList = list;
      PROCESS_INFORMATION process = {};
      started = ::CreateProcessW(path, command.data(), nullptr, nullptr, TRUE,
                                 EXTENDED_STARTUPINFO_PRESENT, nullptr,
                                 nullptr, &startup.StartupInfo, &process);
      if (started) {
        ::CloseHandle(process.hThread);
        ::CloseHandle(process.hProcess);
      }
    }
    ::DeleteProcThreadAttributeList(list);
  }
  ::CloseHandle(self);
  return started;
}

void WaitForEarlierCopy() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  HANDLE earlier = nullptr;
  for (int i = 1; argv != nullptr && i < argc; i++) {
    if (StartsWith(argv[i], kAfterExitFlag)) {
      earlier = reinterpret_cast<HANDLE>(static_cast<uintptr_t>(
          ::wcstoull(argv[i] + ::wcslen(kAfterExitFlag), nullptr, 10)));
    }
  }
  ::LocalFree(argv);
  // Only a process handle is waited on: a number typed by hand names
  // whatever handle this process happens to hold, or none.
  if (earlier == nullptr || ::GetProcessId(earlier) == 0) return;
  if (::WaitForSingleObject(earlier, kLeaveMs) == WAIT_TIMEOUT) {
    ::TerminateProcess(earlier, 1);
    ::WaitForSingleObject(earlier, kLeaveMs);
  }
  ::CloseHandle(earlier);
}

bool IsRunnerArgument(const std::string& argument) {
  return argument.rfind("--after-exit=", 0) == 0;
}
