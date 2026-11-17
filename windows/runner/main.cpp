#include <app_links/app_links_plugin_c_api.h>
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <shellapi.h>

#include "echo_canceller.h"
#include "flutter_window.h"
#include "single_instance.h"
#include "startup_guard.h"
#include "utils.h"
#include "velopack_hooks.h"

namespace {

// Whether this copy was started to open a rift:// link — the browser's "Open
// in Rift", which runs `RiftChat.exe "<link>"` (registerInviteScheme). Only
// then is a link handed to the copy already running: SendAppLinkToInstance
// raises whichever window it finds, and a plain second launch has its own way
// to do that (SingleInstance).
bool LaunchedWithLink() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  const bool link =
      argv != nullptr && argc == 2 && ::_wcsnicmp(argv[1], L"rift:", 5) == 0;
  ::LocalFree(argv);
  return link;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Before the single-instance check: Velopack runs these while Rift may be
  // open, and they must not be taken for a second launch.
  if (HandleVelopackHook()) return EXIT_SUCCESS;

  SingleInstance single_instance;
  if (!single_instance.Acquire()) {
    // Without this the running copy came forward and the invite was lost.
    if (LaunchedWithLink()) SendAppLinkToInstance();
    return EXIT_SUCCESS;
  }
  CheckLastStartAndMark();

  ApplyInstalledAppUserModelId();
  RemoveLegacyInstall();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  // Before flutter_webrtc makes its audio device (echo_canceller.h).
  KeepWebRtcEchoCanceller();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // Dart on this thread, the window's, as Flutter runs it by default
  // (CALLS.md, "Rift beside a game"). Rift ran it on a thread of its own
  // from Oct 2026, when Dart here woke this thread 1,000 times a second;
  // Flutter 3.50 no longer does that. Being tested Nov 2026 against the
  // freeze after minimising (report 73381cb4).
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnPlatformThread);

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"rift", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  single_instance.ListenForLaunches(window.GetHandle());

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ReleaseWebRtcEchoCanceller();
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
