#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "seen_watch.h"
#include "tray_icon.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // EventChannel that forwards Win32 global keyboard hook events to Dart.
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> ptt_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> ptt_event_sink_;

  // Configure |ptt_channel_| against the running Flutter engine.
  void SetupPttChannel();

  // EventChannel that tells Dart whether anybody can see this window, while
  // Dart listens (SeenWatch).
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      seen_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
      seen_event_sink_;
  std::unique_ptr<SeenWatch> seen_watch_;

  // Configure |seen_channel_| against the running Flutter engine.
  void SetupSeenChannel();

  // MethodChannel between Dart and the tray icon: Dart adds and removes it,
  // and hears what was chosen on it.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> tray_channel_;
  std::unique_ptr<TrayIcon> tray_icon_;

  // Configure |tray_channel_| against the running Flutter engine.
  void SetupTrayChannel();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
