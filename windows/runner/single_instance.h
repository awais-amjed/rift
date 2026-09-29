#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

// Posted to the running copy's window when Rift is launched again on the same
// profile: bring the window back, from the tray too.
static constexpr UINT kWmShowRunningCopy = WM_APP + 101;

// One running copy per profile.
//
// A second copy cannot run beside the first: Windows file locks are
// mandatory, so the first copy's lock on the profile's hydrated_box.lock fails
// the second one's write to it, and main() throws before the window is ever
// shown — a process with no window that only Task Manager can end, and one
// more for every click on the icon. So a second launch hands over to the
// running copy and exits, the way a single-window desktop app is expected to.
//
// The profile is the same one Dart resolves (StorageNamespace): RIFT_PROFILE
// when set, otherwise `dev` for a debug build and none for release. Copies on
// different profiles still run side by side.
class SingleInstance {
 public:
  SingleInstance() = default;
  ~SingleInstance();
  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  // True when this is the only copy on its profile. False when another copy
  // is already running; it has been asked to show itself, and this one should
  // exit.
  bool Acquire();

  // Shows |window| each time a later launch asks for it.
  void ListenForLaunches(HWND window);

 private:
  static void CALLBACK OnLaunch(PVOID window, BOOLEAN timed_out);

  HANDLE running_ = nullptr;
  HANDLE launched_ = nullptr;
  HANDLE wait_ = nullptr;
};

#endif  // RUNNER_SINGLE_INSTANCE_H_
