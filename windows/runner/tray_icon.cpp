#include "tray_icon.h"

#include <wchar.h>

#include <utility>

#include "resource.h"

namespace {

constexpr wchar_t kWindowClass[] = L"RIFT_TRAY_WINDOW";
constexpr wchar_t kTooltip[] = L"Rift";
constexpr UINT kWmTrayEvent = WM_APP + 1;
constexpr UINT kIconId = 1;
constexpr UINT kMenuShow = 1;
constexpr UINT kMenuQuit = 2;

}  // namespace

TrayIcon::TrayIcon(std::function<void(Choice)> on_choice)
    : on_choice_(std::move(on_choice)) {
  HINSTANCE instance = ::GetModuleHandleW(nullptr);

  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = WndProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kWindowClass;
  ::RegisterClassW(&window_class);

  // A WS_POPUP that is never shown, not a message-only window: it has to hear
  // the TaskbarCreated broadcast, and broadcasts skip message-only windows.
  window_ = ::CreateWindowExW(WS_EX_TOOLWINDOW, kWindowClass, L"", WS_POPUP, 0,
                              0, 0, 0, nullptr, nullptr, instance, this);
  if (window_ == nullptr) return;

  taskbar_created_ = ::RegisterWindowMessageW(L"TaskbarCreated");
  // An elevated Rift would otherwise have this filtered out, coming from an
  // ordinary Explorer.
  ::ChangeWindowMessageFilterEx(window_, taskbar_created_, MSGFLT_ALLOW,
                                nullptr);

  icon_ = static_cast<HICON>(::LoadImageW(
      instance, MAKEINTRESOURCEW(IDI_TRAY_ICON), IMAGE_ICON,
      ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR));

  data_.cbSize = sizeof(data_);
  data_.hWnd = window_;
  data_.uID = kIconId;
  data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data_.uCallbackMessage = kWmTrayEvent;
  data_.hIcon = icon_;
  ::wcscpy_s(data_.szTip, kTooltip);
  AddToShell();
}

TrayIcon::~TrayIcon() {
  *alive_ = false;
  if (window_ != nullptr) {
    ::Shell_NotifyIconW(NIM_DELETE, &data_);
    ::DestroyWindow(window_);
  }
  if (icon_ != nullptr) ::DestroyIcon(icon_);
}

void TrayIcon::AddToShell() {
  // Failing is not the end of it: at sign-in the taskbar may not be there yet,
  // and TaskbarCreated tries again.
  ::Shell_NotifyIconW(NIM_ADD, &data_);
}

void TrayIcon::OpenMenu() {
  if (menu_open_) return;
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) return;
  ::AppendMenuW(menu, MF_STRING, kMenuShow, L"Show Rift");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuQuit, L"Quit");

  POINT cursor = {};
  ::GetCursorPos(&cursor);

  // Without being foreground, the menu would stay open after a click
  // elsewhere; the WM_NULL after it is the other half of the documented
  // recipe, so that a second click opens it again.
  HWND window = window_;
  ::SetForegroundWindow(window);
  auto alive = alive_;
  menu_open_ = true;
  const UINT picked = static_cast<UINT>(::TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_RIGHTALIGN,
      cursor.x, cursor.y, 0, window, nullptr));
  ::DestroyMenu(menu);
  if (!*alive) return;
  menu_open_ = false;
  ::PostMessageW(window, WM_NULL, 0, 0);

  if (picked == kMenuShow) on_choice_(Choice::kShow);
  if (picked == kMenuQuit) on_choice_(Choice::kQuit);
}

LRESULT TrayIcon::Handle(UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  if (message == kWmTrayEvent) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
        on_choice_(Choice::kShow);
        break;
      case WM_RBUTTONUP:
        OpenMenu();
        break;
    }
    return 0;
  }
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    AddToShell();
    return 0;
  }
  return ::DefWindowProcW(window_, message, wparam, lparam);
}

LRESULT CALLBACK TrayIcon::WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                   LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    auto* that = static_cast<TrayIcon*>(create->lpCreateParams);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(that));
    that->window_ = hwnd;
  } else if (message == WM_NCDESTROY) {
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
  } else if (auto* that = reinterpret_cast<TrayIcon*>(
                 ::GetWindowLongPtrW(hwnd, GWLP_USERDATA))) {
    return that->Handle(message, wparam, lparam);
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}
