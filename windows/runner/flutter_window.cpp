#include "flutter_window.h"

#include <shellapi.h>

#include <optional>

#include <flutter/encodable_value.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "global_key_hook.h"
#include "noise_filter/noise_filter.h"
#include "single_instance.h"

namespace {

bool StartedMinimized() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  bool minimized = false;
  for (int i = 1; argv != nullptr && i < argc; i++) {
    if (::wcscmp(argv[i], L"--minimized") == 0) minimized = true;
  }
  ::LocalFree(argv);
  return minimized;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  rift::InstallNoiseFilter();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetupPttChannel();

  // A start at sign-in that should stay in the tray never shows the window:
  // LoginLaunch puts `--minimized` in the Run value when the person asked for
  // that, and the tray's Show Rift shows it through window_manager.
  if (!StartedMinimized()) {
    flutter_controller_->engine()->SetNextFrameCallback([&]() {
      this->Show();
    });
  }

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  GlobalKeyHook::Instance().Stop();
  ptt_event_sink_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    case kWmPttKeyEvent:
      if (ptt_event_sink_) {
        flutter::EncodableMap args{
            {flutter::EncodableValue("vk_code"),
             flutter::EncodableValue(static_cast<int>(wparam))},
            {flutter::EncodableValue("is_down"),
             flutter::EncodableValue(lparam != 0)},
        };
        ptt_event_sink_->Success(flutter::EncodableValue(args));
      }
      return 0;

    case kWmShowRunningCopy:
      ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
      ::SetForegroundWindow(hwnd);
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetupPttChannel() {
  ptt_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "rift/ptt_keys",
          &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      // onListen: Dart subscriber connected — install the global hook.
      [this](const flutter::EncodableValue* /*arguments*/,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                 events)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        ptt_event_sink_ = std::move(events);
        GlobalKeyHook::Instance().Start(GetHandle());
        return nullptr;
      },
      // onCancel: Dart subscriber disconnected — remove the hook.
      [this](const flutter::EncodableValue* /*arguments*/)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        GlobalKeyHook::Instance().Stop();
        ptt_event_sink_ = nullptr;
        return nullptr;
      });

  ptt_channel_->SetStreamHandler(std::move(handler));
}

