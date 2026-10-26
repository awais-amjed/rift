#ifndef RUNNER_SEEN_WATCH_H_
#define RUNNER_SEEN_WATCH_H_

#include <windows.h>

#include <functional>

// Application-defined window message posted to the Flutter window when the
// foreground window changes, or a window moves, is resized or is minimised,
// so SeenWatch can look again on the window's own thread.
static constexpr UINT kWmSeenCheck = WM_APP + 102;

// Whether anybody can see Rift's window. Not when it is minimised or hidden
// to the tray, nor when another app's window is in front and covers all of
// Rift that is on screen, as a game in fullscreen or a maximised browser
// does. Rift on another monitor, or only partly covered, can be seen. Dart
// turns a watched stream's picture off while it cannot (AppSeenListener).
// Minimised is here as well as in Dart's app lifecycle because on Windows the
// lifecycle never said so (CALLS.md, "Watching while Rift cannot be seen").
//
// Looks again whenever the foreground window changes, a window finishes
// moving or sizing, or one is minimised or restored (WinEvent hooks, called on
// this thread), when Rift is shown, hidden, resized or moved in the order
// of windows, and once a second while another app is in front or Rift
// cannot be seen, which is what catches a game going fullscreen after it
// took the foreground, or a window maximised from the keyboard.
class SeenWatch {
 public:
  // Starts watching |window|; |on_change| is called with the first answer
  // and with every change after it, on the window's thread.
  SeenWatch(HWND window, std::function<void(bool)> on_change);
  ~SeenWatch();

  SeenWatch(const SeenWatch&) = delete;
  SeenWatch& operator=(const SeenWatch&) = delete;

  // Looks again, and reports a change. The window calls it on kWmSeenCheck
  // and on its timer.
  void Check();

  // The timer the window passes back to Check.
  static constexpr UINT_PTR kTimerId = 0x52535757;  // 'RSWW'

 private:
  bool Seen() const;

  static void CALLBACK OnWinEvent(HWINEVENTHOOK hook, DWORD event, HWND hwnd,
                                  LONG id_object, LONG id_child,
                                  DWORD event_thread, DWORD event_time);

  HWND window_;
  std::function<void(bool)> on_change_;
  HWINEVENTHOOK hooks_[3] = {};
  bool seen_ = true;
  bool reported_ = false;
  bool polling_ = false;
};

#endif  // RUNNER_SEEN_WATCH_H_
