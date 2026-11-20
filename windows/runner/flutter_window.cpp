#include "flutter_window.h"

#include <shellapi.h>

#include <optional>

#include <flutter/encodable_value.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "global_key_hook.h"
#include "call_clip/call_clip.h"
#include "noise_filter/noise_filter.h"
#include "relaunch.h"
#include "single_instance.h"
#include "startup_guard.h"
#include "stream_draw.h"

namespace {

// A test's stand-in for a driver reset: the loss is said this many seconds
// after the start, while the device is in fact fine. Only a test sets it.
constexpr UINT_PTR kFakeGpuLossTimer = 0x52474c;  // "RGL"

UINT FakeGpuLossSeconds() {
  wchar_t value[16] = {};
  if (::GetEnvironmentVariableW(L"RIFT_FAKE_GPU_LOSS_SECONDS", value,
                                ARRAYSIZE(value)) == 0) {
    return 0;
  }
  return static_cast<UINT>(::wcstoul(value, nullptr, 10));
}

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
  rift::InstallCallClip();
  stream_textures_ =
      std::make_unique<rift::StreamTextures>(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetupPttChannel();
  SetupSeenChannel();
  SetupTrayChannel();
  SetupMicBadge();
  SetupGpuWatch();

  // The first frame is where a start counts as finished (startup_guard.h).
  // A start at sign-in that should stay in the tray never shows the window:
  // LoginLaunch puts `--minimized` in the Run value when the person asked for
  // that, and the tray's Show Rift shows it through window_manager.
  const bool minimized = StartedMinimized();
  flutter_controller_->engine()->SetNextFrameCallback([this, minimized]() {
    MarkStartFinished();
    if (!minimized) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  gpu_watch_ = nullptr;
  tray_icon_ = nullptr;
  mic_badge_ = nullptr;
  GlobalKeyHook::Instance().Stop();
  ptt_event_sink_ = nullptr;
  seen_watch_ = nullptr;
  seen_event_sink_ = nullptr;
  stream_textures_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Shown, hidden to the tray, minimised, restored, moved in the order of
  // windows: sent once the window is in its new state, and looked at after.
  // Ahead of Flutter, which may end the message here.
  if (message == WM_WINDOWPOSCHANGED && seen_watch_) {
    ::PostMessageW(hwnd, kWmSeenCheck, 0, 0);
  }
  if (mic_badge_) mic_badge_->OnMessage(message);

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
             flutter::EncodableValue(lparam == 1)},
            {flutter::EncodableValue("by_check"),
             flutter::EncodableValue(lparam == 2)},
        };
        ptt_event_sink_->Success(flutter::EncodableValue(args));
      }
      return 0;

    case kWmSeenCheck:
      if (seen_watch_) seen_watch_->Check();
      return 0;

    case kWmGpuLost:
      StreamLog("gpu: Windows signalled the loss %llu ms ago",
                ::GetTickCount64() - static_cast<ULONGLONG>(lparam));
      SayGpuLost(gpu_watch_ ? gpu_watch_->Reason() : S_OK);
      return 0;

    case WM_ACTIVATE:
      // Where Windows cannot signal the loss, it is found when someone comes
      // back to the window to see why it is white.
      if (LOWORD(wparam) != WA_INACTIVE && gpu_watch_ &&
          !gpu_watch_->listening() && gpu_watch_->Reason() != S_OK) {
        SayGpuLost(gpu_watch_->Reason());
      }
      break;

    case WM_TIMER:
      if (wparam == SeenWatch::kTimerId) {
        if (seen_watch_) seen_watch_->Check();
        return 0;
      }
      if (wparam == kFakeGpuLossTimer) {
        ::KillTimer(hwnd, kFakeGpuLossTimer);
        StreamLog("gpu: a test fakes the loss of Flutter's GPU");
        SayGpuLost(DXGI_ERROR_DEVICE_RESET);
        return 0;
      }
      break;

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

void FlutterWindow::SetupSeenChannel() {
  seen_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "rift/window_seen",
          &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      // onListen: Dart wants to know — start watching, which answers at once.
      [this](const flutter::EncodableValue* /*arguments*/,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                 events)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        seen_event_sink_ = std::move(events);
        // Gone before the next starts: the two share the timer and the hook's
        // window.
        seen_watch_ = nullptr;
        seen_watch_ = std::make_unique<SeenWatch>(
            GetHandle(), [this](bool seen) {
              if (seen_event_sink_) {
                seen_event_sink_->Success(flutter::EncodableValue(seen));
              }
            });
        return nullptr;
      },
      // onCancel: nobody is listening — stop watching.
      [this](const flutter::EncodableValue* /*arguments*/)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        seen_watch_ = nullptr;
        seen_event_sink_ = nullptr;
        return nullptr;
      });

  seen_channel_->SetStreamHandler(std::move(handler));
}

void FlutterWindow::SetupTrayChannel() {
  tray_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "rift/tray",
          &flutter::StandardMethodCodec::GetInstance());

  tray_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "add") {
          if (!tray_icon_) {
            tray_icon_ = std::make_unique<TrayIcon>(
                [this](TrayIcon::Choice choice) {
                  tray_channel_->InvokeMethod(
                      choice == TrayIcon::Choice::kShow ? "show" : "quit",
                      nullptr);
                });
            tray_icon_->SetMicOn(mic_on_);
          }
          result->Success(flutter::EncodableValue(tray_icon_->ok()));
        } else if (call.method_name() == "remove") {
          tray_icon_ = nullptr;
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::SetupMicBadge() {
  mic_badge_ = std::make_unique<MicBadge>(GetHandle());
  mic_badge_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "rift/mic_badge",
          &flutter::StandardMethodCodec::GetInstance());
  mic_badge_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "set") {
          result->NotImplemented();
          return;
        }
        const auto* on = std::get_if<bool>(call.arguments());
        mic_on_ = on != nullptr && *on;
        if (mic_badge_) mic_badge_->Set(mic_on_);
        if (tray_icon_) tray_icon_->SetMicOn(mic_on_);
        result->Success();
      });
}

void FlutterWindow::SetupGpuWatch() {
  gpu_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "rift/gpu",
          &flutter::StandardMethodCodec::GetInstance());
  gpu_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "relaunch") {
          // Out of sight again if it was out of sight now: a start at
          // sign-in waiting in the tray stays there.
          const bool minimized = !::IsWindowVisible(GetHandle());
          const bool started = RelaunchAfterExit(minimized);
          StreamLog(started ? "gpu: started Rift again, to take over once "
                              "this copy leaves"
                            : "gpu: could not start Rift again");
          result->Success(flutter::EncodableValue(started));
        } else {
          result->NotImplemented();
        }
      });

  IDXGIAdapter* adapter = nullptr;
  if (flutter_controller_->engine()->GetGraphicsAdapter(&adapter) &&
      adapter != nullptr) {
    auto device = GpuWatch::MakeDevice(adapter);
    adapter->Release();
    if (device) {
      gpu_watch_ = std::make_unique<GpuWatch>(GetHandle(), std::move(device));
    }
  }
  if (!gpu_watch_) {
    StreamLog("gpu: no device to watch Flutter's GPU with");
  } else if (!gpu_watch_->listening()) {
    StreamLog("gpu: Windows cannot signal the loss of Flutter's GPU; it is "
              "looked for when the window is activated");
  }

  if (const UINT seconds = FakeGpuLossSeconds()) {
    ::SetTimer(GetHandle(), kFakeGpuLossTimer, seconds * 1000, nullptr);
  }
}

void FlutterWindow::SayGpuLost(HRESULT reason) {
  if (gpu_lost_said_ || !gpu_channel_) return;
  gpu_lost_said_ = true;
  StreamLog("gpu: the GPU Flutter draws with was lost (%08lx); Flutter "
            "cannot draw on it again",
            reason);
  gpu_channel_->InvokeMethod(
      "lost", std::make_unique<flutter::EncodableValue>(
                  static_cast<int64_t>(static_cast<uint32_t>(reason))));
}
