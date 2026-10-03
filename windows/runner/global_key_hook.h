#ifndef RUNNER_GLOBAL_KEY_HOOK_H_
#define RUNNER_GLOBAL_KEY_HOOK_H_

#include <windows.h>

#include <atomic>
#include <thread>

// Application-defined window message sent by the low-level hook thread to the
// Flutter window on every key or mouse button down/up event.
//   WPARAM = Win32 virtual-key code (DWORD); VK_LBUTTON..VK_XBUTTON2 for a
//            mouse button
//   LPARAM = 1 for key-down, 0 for key-up
static constexpr UINT kWmPttKeyEvent = WM_APP + 100;

// Singleton that installs WH_KEYBOARD_LL and WH_MOUSE_LL hooks on a dedicated
// thread so that key and mouse button events are received even when the
// application is not in the foreground.
// The hook thread posts kWmPttKeyEvent messages to |target_hwnd| for every
// key-down and key-up event; the main Flutter window processes those messages
// and forwards them to Dart through an EventChannel.
class GlobalKeyHook {
 public:
  static GlobalKeyHook& Instance();

  // Install the hook and begin posting messages to |hwnd|.
  // Safe to call multiple times; a second call is a no-op.
  void Start(HWND hwnd);

  // Uninstall the hook and join the hook thread.
  // Safe to call even if Start() was never called.
  void Stop();

  bool IsRunning() const { return running_.load(); }

 private:
  GlobalKeyHook() = default;
  ~GlobalKeyHook() { Stop(); }
  GlobalKeyHook(const GlobalKeyHook&) = delete;
  GlobalKeyHook& operator=(const GlobalKeyHook&) = delete;

  static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam,
                                                LPARAM lParam);
  static LRESULT CALLBACK LowLevelMouseProc(int nCode, WPARAM wParam,
                                             LPARAM lParam);

  std::thread hook_thread_;
  DWORD hook_thread_id_ = 0;
  std::atomic<bool> running_{false};
};

#endif  // RUNNER_GLOBAL_KEY_HOOK_H_

