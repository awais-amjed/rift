#include "global_key_hook.h"

// ----------------------------------------------------------------------------
// Module-level statics used by the static hook callback
// ----------------------------------------------------------------------------

// Window that receives kWmPttKeyEvent messages. Written once in Start() on the
// main thread before the hook thread reads it, so no synchronization needed.
static HWND g_target_hwnd = nullptr;

// The installed hook handle.  Owned by the hook thread.
static HHOOK g_hook = nullptr;

// ----------------------------------------------------------------------------
// GlobalKeyHook implementation
// ----------------------------------------------------------------------------

GlobalKeyHook& GlobalKeyHook::Instance() {
  static GlobalKeyHook instance;
  return instance;
}

LRESULT CALLBACK GlobalKeyHook::LowLevelKeyboardProc(int nCode, WPARAM wParam,
                                                      LPARAM lParam) {
  if (nCode >= 0 && g_target_hwnd != nullptr) {
    const auto* kbd = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lParam);
    const bool is_down =
        (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);
    const bool is_up =
        (wParam == WM_KEYUP || wParam == WM_SYSKEYUP);

    if (is_down || is_up) {
      // WPARAM carries the virtual-key code, LPARAM carries the direction.
      PostMessage(g_target_hwnd, kWmPttKeyEvent,
                  static_cast<WPARAM>(kbd->vkCode),
                  static_cast<LPARAM>(is_down ? 1 : 0));
    }
  }
  return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

void GlobalKeyHook::Start(HWND hwnd) {
  if (running_.exchange(true)) {
    return;  // Already running
  }

  g_target_hwnd = hwnd;

  // Use a Win32 auto-reset event so the calling thread can wait until the hook
  // thread has recorded its own thread-id (needed later for WM_QUIT).
  HANDLE ready_event = CreateEvent(nullptr, FALSE, FALSE, nullptr);

  hook_thread_ = std::thread([this, ready_event]() {
    hook_thread_id_ = GetCurrentThreadId();
    SetEvent(ready_event);

    g_hook = SetWindowsHookEx(WH_KEYBOARD_LL, LowLevelKeyboardProc,
                               nullptr, 0);
    if (g_hook) {
      MSG msg;
      while (GetMessage(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
      }
      UnhookWindowsHookEx(g_hook);
      g_hook = nullptr;
    }
  });

  // Wait until the hook thread has stored its ID.
  WaitForSingleObject(ready_event, INFINITE);
  CloseHandle(ready_event);
}

void GlobalKeyHook::Stop() {
  if (!running_.exchange(false)) {
    return;  // Not running
  }

  g_target_hwnd = nullptr;

  if (hook_thread_id_ != 0) {
    PostThreadMessage(hook_thread_id_, WM_QUIT, 0, 0);
    hook_thread_id_ = 0;
  }

  if (hook_thread_.joinable()) {
    hook_thread_.join();
  }
}

