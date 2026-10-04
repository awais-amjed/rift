#include "global_key_hook.h"

// ----------------------------------------------------------------------------
// Module-level statics used by the static hook callback
// ----------------------------------------------------------------------------

// Window that receives kWmPttKeyEvent messages. Written once in Start() on the
// main thread before the hook thread reads it, so no synchronization needed.
static HWND g_target_hwnd = nullptr;

// The installed hook handles.  Owned by the hook thread.
static HHOOK g_hook = nullptr;
static HHOOK g_mouse_hook = nullptr;

// ----------------------------------------------------------------------------
// Held-key check
// ----------------------------------------------------------------------------
//
// The hook can miss a key-up. Windows does not run a low-level hook for input
// going to an elevated window — a game started as administrator, Task Manager
// — so a push-to-talk key let go there is never reported, and Dart goes on
// believing it is held: the mic stays open, and the next press changes
// nothing because the key is already "down". So while the hook believes any
// key is down, a timer on the hook thread asks Windows whether it still is,
// and reports the release itself when it is not.

// When each key the hook reported down went down, 0 for keys that are up.
// Hook thread only: the procedures and the timer both run on it.
static ULONGLONG g_down_since[256] = {};
static UINT_PTR g_held_check_timer = 0;

// How often a held key is checked, and how long a fresh press is left alone
// first: the hook runs before Windows records the press, so asking at once
// could hear the key as still up.
static constexpr UINT kHeldCheckMs = 100;

static void PostKey(UINT vk, bool is_down) {
  // WPARAM carries the virtual-key code, LPARAM carries the direction.
  PostMessage(g_target_hwnd, kWmPttKeyEvent, static_cast<WPARAM>(vk),
              static_cast<LPARAM>(is_down ? 1 : 0));
}

static VOID CALLBACK CheckHeldKeys(HWND, UINT, UINT_PTR, DWORD) {
  const ULONGLONG now = GetTickCount64();
  bool any_held = false;
  for (UINT vk = 0; vk < 256; ++vk) {
    const ULONGLONG since = g_down_since[vk];
    if (since == 0) continue;
    if (now - since < kHeldCheckMs || (GetAsyncKeyState(vk) & 0x8000)) {
      any_held = true;
      continue;
    }
    g_down_since[vk] = 0;
    if (g_target_hwnd != nullptr) PostKey(vk, false);
  }
  if (!any_held && g_held_check_timer != 0) {
    KillTimer(nullptr, g_held_check_timer);
    g_held_check_timer = 0;
  }
}

// Posts a key or button event and keeps the held-key record in step with it.
static void ReportKey(UINT vk, bool is_down) {
  PostKey(vk, is_down);
  // The main buttons are left out: Windows reports their logical state to the
  // hook but their physical one to GetAsyncKeyState, and the two differ on a
  // mouse set up for the left hand.
  if (vk >= 256 || vk == VK_LBUTTON || vk == VK_RBUTTON) return;
  if (!is_down) {
    g_down_since[vk] = 0;
    return;
  }
  // Auto-repeat sends more downs; the press is when it first went down.
  if (g_down_since[vk] == 0) g_down_since[vk] = GetTickCount64();
  if (g_held_check_timer == 0) {
    g_held_check_timer = SetTimer(nullptr, 0, kHeldCheckMs, CheckHeldKeys);
  }
}

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
      ReportKey(static_cast<UINT>(kbd->vkCode), is_down);
    }
  }
  return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

LRESULT CALLBACK GlobalKeyHook::LowLevelMouseProc(int nCode, WPARAM wParam,
                                                   LPARAM lParam) {
  if (nCode >= 0 && g_target_hwnd != nullptr) {
    // Every pointer move passes through here too, so anything that is not a
    // button goes straight on.
    UINT vk = 0;
    bool is_down = false;
    switch (wParam) {
      case WM_LBUTTONDOWN: is_down = true; [[fallthrough]];
      case WM_LBUTTONUP: vk = VK_LBUTTON; break;
      case WM_RBUTTONDOWN: is_down = true; [[fallthrough]];
      case WM_RBUTTONUP: vk = VK_RBUTTON; break;
      case WM_MBUTTONDOWN: is_down = true; [[fallthrough]];
      case WM_MBUTTONUP: vk = VK_MBUTTON; break;
      case WM_XBUTTONDOWN: is_down = true; [[fallthrough]];
      case WM_XBUTTONUP: {
        const auto* mouse = reinterpret_cast<const MSLLHOOKSTRUCT*>(lParam);
        vk = HIWORD(mouse->mouseData) == XBUTTON1 ? VK_XBUTTON1 : VK_XBUTTON2;
        break;
      }
    }
    if (vk != 0) {
      // The same message as a key: a button's VK_*BUTTON code is one more
      // virtual-key code, and Dart compares codes without caring which.
      ReportKey(vk, is_down);
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
    // Push-to-talk on a mouse's side buttons. Windows calls this for every
    // move as well, on this thread, so the procedure has to stay trivial.
    g_mouse_hook =
        SetWindowsHookEx(WH_MOUSE_LL, LowLevelMouseProc, nullptr, 0);
    if (g_hook || g_mouse_hook) {
      MSG msg;
      while (GetMessage(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
      }
    }
    if (g_hook) UnhookWindowsHookEx(g_hook);
    if (g_mouse_hook) UnhookWindowsHookEx(g_mouse_hook);
    g_hook = nullptr;
    g_mouse_hook = nullptr;
    if (g_held_check_timer != 0) KillTimer(nullptr, g_held_check_timer);
    g_held_check_timer = 0;
    for (auto& since : g_down_since) since = 0;
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

