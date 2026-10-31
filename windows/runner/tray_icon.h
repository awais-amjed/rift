#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>
#include <shellapi.h>

#include <functional>
#include <memory>

// Rift's icon in the notification area, with its Show Rift / Quit menu.
//
// Here on the main thread rather than in Dart: a window belongs to the thread
// that made it, and Dart's thread runs no message loop (main.cpp), so an icon
// made there never hears a click. It has a hidden window of its own to make
// foreground for the menu: making Rift's foreground would raise Rift over
// whatever the person was doing, just for opening a menu.
class TrayIcon {
 public:
  enum class Choice { kShow, kQuit };

  // |on_choice| runs on the main thread, for a left click (kShow) or a pick
  // from the menu.
  explicit TrayIcon(std::function<void(Choice)> on_choice);
  ~TrayIcon();

  TrayIcon(const TrayIcon&) = delete;
  TrayIcon& operator=(const TrayIcon&) = delete;

  // False when the window behind the icon could not be made. An icon the
  // shell refuses for now still counts: it goes up when a taskbar appears.
  bool ok() const { return window_ != nullptr; }

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;
  LRESULT Handle(UINT message, WPARAM wparam, LPARAM lparam) noexcept;

  void AddToShell();
  void OpenMenu();

  std::function<void(Choice)> on_choice_;
  HWND window_ = nullptr;
  NOTIFYICONDATAW data_ = {};
  HICON icon_ = nullptr;
  // Registered by Explorer: broadcast when a taskbar starts, which forgets
  // every icon. Hidden windows hear it; message-only ones would not.
  UINT taskbar_created_ = 0;
  bool menu_open_ = false;
  // Cleared by the destructor. The menu's own message loop runs Flutter's
  // tasks, so Rift can quit, and this go away, while the menu is open.
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
};

#endif  // RUNNER_TRAY_ICON_H_
