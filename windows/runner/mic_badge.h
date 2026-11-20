#ifndef RUNNER_MIC_BADGE_H_
#define RUNNER_MIC_BADGE_H_

#include <windows.h>
#include <shobjidl.h>
#include <wrl/client.h>

// The mic on Rift's taskbar button while people in the call can hear the
// person (MicBadgeListener in Dart says when): a taskbar overlay, the corner
// badge Windows draws over an app's button.
//
// The taskbar forgets an overlay whenever it makes the button again, which it
// does each time the window comes back from the tray and when Explorer
// starts, and says so with TaskbarButtonCreated; the badge is put back then.
class MicBadge {
 public:
  explicit MicBadge(HWND window);
  ~MicBadge();

  MicBadge(const MicBadge&) = delete;
  MicBadge& operator=(const MicBadge&) = delete;

  void Set(bool on);

  // For every message to the window; puts the badge back when the taskbar
  // made the button again.
  void OnMessage(UINT message);

 private:
  void Apply();

  HWND window_;
  UINT button_created_ = 0;
  Microsoft::WRL::ComPtr<ITaskbarList3> taskbar_;
  HICON icon_ = nullptr;
  bool on_ = false;
};

#endif  // RUNNER_MIC_BADGE_H_
