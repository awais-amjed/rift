#include "seen_watch.h"

#include <dwmapi.h>

namespace {

// The one window being watched, for the WinEvent callback, which carries no
// context of its own. Rift has one window and one watch.
HWND g_watched = nullptr;

// What of |window| is drawn, without the invisible resize borders
// GetWindowRect counts: a maximised window's rectangle there reaches past its
// monitor by those borders.
RECT DrawnRect(HWND window) {
  RECT rect{};
  if (FAILED(::DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS,
                                     &rect, sizeof(rect)))) {
    ::GetWindowRect(window, &rect);
  }
  return rect;
}

// Whether the window in front could hide what is under it at all. The
// desktop is the foreground when it is clicked, and lies under everything;
// a click-through or see-through overlay shows what is behind it; a cloaked
// window is not drawn.
bool CanCover(HWND front) {
  if (front == ::GetShellWindow()) return false;
  wchar_t name[32] = {};
  ::GetClassNameW(front, name, 32);
  if (::wcscmp(name, L"Progman") == 0 || ::wcscmp(name, L"WorkerW") == 0) {
    return false;
  }
  const LONG_PTR ex_style = ::GetWindowLongPtrW(front, GWL_EXSTYLE);
  if (ex_style & WS_EX_TRANSPARENT) return false;
  if (ex_style & WS_EX_LAYERED) {
    // Drawn with its own per-pixel alpha (UpdateLayeredWindow) when this
    // fails: anything may show through.
    BYTE alpha = 0;
    DWORD flags = 0;
    if (!::GetLayeredWindowAttributes(front, nullptr, &alpha, &flags)) {
      return false;
    }
    if ((flags & LWA_COLORKEY) || ((flags & LWA_ALPHA) && alpha < 255)) {
      return false;
    }
  }
  DWORD cloaked = 0;
  if (SUCCEEDED(::DwmGetWindowAttribute(front, DWMWA_CLOAKED, &cloaked,
                                        sizeof(cloaked))) &&
      cloaked != 0) {
    return false;
  }
  return true;
}

// Whether |front| is above |window| in the order windows are drawn.
bool Above(HWND front, HWND window) {
  for (HWND h = ::GetWindow(window, GW_HWNDPREV); h != nullptr;
       h = ::GetWindow(h, GW_HWNDPREV)) {
    if (h == front) return true;
  }
  return false;
}

}  // namespace

SeenWatch::SeenWatch(HWND window, std::function<void(bool)> on_change)
    : window_(window), on_change_(std::move(on_change)) {
  g_watched = window_;
  // Rift's own events too: it taking the foreground is what uncovers it.
  const DWORD flags = WINEVENT_OUTOFCONTEXT;
  hooks_[0] = ::SetWinEventHook(EVENT_SYSTEM_FOREGROUND,
                                EVENT_SYSTEM_FOREGROUND, nullptr, OnWinEvent,
                                0, 0, flags);
  hooks_[1] = ::SetWinEventHook(EVENT_SYSTEM_MOVESIZEEND,
                                EVENT_SYSTEM_MOVESIZEEND, nullptr, OnWinEvent,
                                0, 0, flags);
  hooks_[2] = ::SetWinEventHook(EVENT_SYSTEM_MINIMIZESTART,
                                EVENT_SYSTEM_MINIMIZEEND, nullptr, OnWinEvent,
                                0, 0, flags);
  Check();
}

SeenWatch::~SeenWatch() {
  for (HWINEVENTHOOK hook : hooks_) {
    if (hook != nullptr) ::UnhookWinEvent(hook);
  }
  if (polling_) ::KillTimer(window_, kTimerId);
  g_watched = nullptr;
}

void SeenWatch::Check() {
  const bool seen = Seen();

  // Polled while another app is in front, and while Rift cannot be seen.
  // With Rift in front and seen, nothing can cover it without taking the
  // foreground first, which the hook hears. Rift takes the foreground before
  // it is shown, though, so a look then finds it hidden, and only a later
  // one finds it back.
  DWORD front_process = 0;
  ::GetWindowThreadProcessId(::GetForegroundWindow(), &front_process);
  const bool poll = !seen || front_process != ::GetCurrentProcessId();
  if (poll != polling_) {
    polling_ = poll;
    if (poll) {
      ::SetTimer(window_, kTimerId, 1000, nullptr);
    } else {
      ::KillTimer(window_, kTimerId);
    }
  }

  if (reported_ && seen == seen_) return;
  seen_ = seen;
  reported_ = true;
  on_change_(seen);
}

bool SeenWatch::Seen() const {
  if (::IsIconic(window_) || !::IsWindowVisible(window_)) return false;
  const HWND front = ::GetForegroundWindow();
  if (front == nullptr) return true;
  DWORD front_process = 0;
  ::GetWindowThreadProcessId(front, &front_process);
  if (front_process == ::GetCurrentProcessId()) return true;
  if (!CanCover(front)) return true;
  // The window in front is not always above: Rift shown from the tray
  // without the foreground, or kept on top, is drawn over it.
  if (!Above(front, window_)) return true;

  // What of Rift is on screen; a part off every monitor is seen by nobody
  // either. A part in a gap between monitors of different sizes still has
  // to be covered, which only errs towards drawing.
  const RECT screen{::GetSystemMetrics(SM_XVIRTUALSCREEN),
                    ::GetSystemMetrics(SM_YVIRTUALSCREEN),
                    ::GetSystemMetrics(SM_XVIRTUALSCREEN) +
                        ::GetSystemMetrics(SM_CXVIRTUALSCREEN),
                    ::GetSystemMetrics(SM_YVIRTUALSCREEN) +
                        ::GetSystemMetrics(SM_CYVIRTUALSCREEN)};
  const RECT rift = DrawnRect(window_);
  RECT shown{};
  if (!::IntersectRect(&shown, &rift, &screen)) return false;
  const RECT over = DrawnRect(front);
  const bool covered = over.left <= shown.left && over.top <= shown.top &&
                       over.right >= shown.right &&
                       over.bottom >= shown.bottom;
  return !covered;
}

void CALLBACK SeenWatch::OnWinEvent(HWINEVENTHOOK /*hook*/, DWORD /*event*/,
                                     HWND /*hwnd*/, LONG id_object,
                                     LONG /*id_child*/,
                                     DWORD /*event_thread*/,
                                     DWORD /*event_time*/) {
  if (id_object != OBJID_WINDOW || g_watched == nullptr) return;
  // Posted rather than checked here: a hook can be called while the window
  // is in the middle of something of its own.
  ::PostMessageW(g_watched, kWmSeenCheck, 0, 0);
}
