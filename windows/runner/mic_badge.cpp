#include "mic_badge.h"

#include "resource.h"

MicBadge::MicBadge(HWND window) : window_(window) {
  button_created_ = ::RegisterWindowMessageW(L"TaskbarButtonCreated");
  // An elevated Rift would otherwise have it filtered out, coming from an
  // ordinary Explorer.
  ::ChangeWindowMessageFilterEx(window_, button_created_, MSGFLT_ALLOW,
                                nullptr);
  // The overlay is drawn at the small icon size.
  icon_ = static_cast<HICON>(::LoadImageW(
      ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_MIC_BADGE), IMAGE_ICON,
      ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR));
}

MicBadge::~MicBadge() {
  if (on_ && taskbar_) taskbar_->SetOverlayIcon(window_, nullptr, nullptr);
  if (icon_ != nullptr) ::DestroyIcon(icon_);
}

void MicBadge::Set(bool on) {
  if (on == on_) return;
  on_ = on;
  Apply();
}

void MicBadge::OnMessage(UINT message) {
  if (button_created_ == 0 || message != button_created_) return;
  // A new Explorer is a new taskbar: the old one's object is no use.
  taskbar_ = nullptr;
  if (on_) Apply();
}

void MicBadge::Apply() {
  if (!taskbar_) {
    Microsoft::WRL::ComPtr<ITaskbarList3> taskbar;
    if (FAILED(::CoCreateInstance(CLSID_TaskbarList, nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&taskbar))) ||
        FAILED(taskbar->HrInit())) {
      return;
    }
    taskbar_ = taskbar;
  }
  // Failing while the window is in the tray is fine: there is no button, and
  // TaskbarButtonCreated brings the badge back with one.
  taskbar_->SetOverlayIcon(window_, on_ ? icon_ : nullptr,
                           on_ ? L"Microphone on" : nullptr);
}
