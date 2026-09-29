#include "single_instance.h"

#include <string>

namespace {

// Named kernel objects for this profile, in the session's own namespace.
std::wstring ObjectName(const wchar_t* what) {
  std::wstring profile;
  const DWORD size = ::GetEnvironmentVariableW(L"RIFT_PROFILE", nullptr, 0);
  if (size > 1) {
    profile.resize(size);
    profile.resize(::GetEnvironmentVariableW(L"RIFT_PROFILE", profile.data(),
                                             size));
  } else {
#ifdef _DEBUG
    profile = L"dev";
#endif
  }
  // A backslash would start a namespace of its own.
  for (auto& c : profile) {
    if (c == L'\\') c = L'_';
  }
  return L"Local\\com.codingfries.rift." + profile + L"." + what;
}

}  // namespace

SingleInstance::~SingleInstance() {
  // Waits for a callback in flight, so none runs after this.
  if (wait_) ::UnregisterWaitEx(wait_, INVALID_HANDLE_VALUE);
  if (launched_) ::CloseHandle(launched_);
  if (running_) ::CloseHandle(running_);
}

bool SingleInstance::Acquire() {
  launched_ = ::CreateEventW(nullptr, FALSE, FALSE,
                             ObjectName(L"launched").c_str());
  running_ = ::CreateMutexW(nullptr, FALSE, ObjectName(L"running").c_str());
  if (running_ == nullptr || ::GetLastError() != ERROR_ALREADY_EXISTS) {
    return true;
  }
  // This process was started by the user, so it may hand the foreground on.
  ::AllowSetForegroundWindow(ASFW_ANY);
  if (launched_) ::SetEvent(launched_);
  return false;
}

void SingleInstance::ListenForLaunches(HWND window) {
  if (launched_ == nullptr || wait_ != nullptr) return;
  ::RegisterWaitForSingleObject(&wait_, launched_, OnLaunch, window, INFINITE,
                                WT_EXECUTEDEFAULT);
}

void CALLBACK SingleInstance::OnLaunch(PVOID window, BOOLEAN /*timed_out*/) {
  ::PostMessage(static_cast<HWND>(window), kWmShowRunningCopy, 0, 0);
}
