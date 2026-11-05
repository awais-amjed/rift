// Checks that KeepWebRtcEchoCanceller hides the Voice Capture DMO from every
// apartment, as libwebrtc's audio device would ask for it: from a thread of
// its own, in the multithreaded apartment. No Flutter. Built and run by
// echo_canceller.ps1.
#include <windows.h>

#include <mediaobj.h>
#include <mmdeviceapi.h>
#include <objbase.h>
#include <wmcodecdsp.h>

#include <cstdio>
#include <thread>

#include "echo_canceller.h"

namespace {

int failures = 0;

#define CHECK(cond, what)                                             \
  do {                                                                \
    if (!(cond)) {                                                    \
      std::printf("FAIL %s:%d: %s: %s\n", __FILE__, __LINE__, #cond, \
                  what);                                              \
      failures++;                                                     \
    }                                                                 \
  } while (0)

// Whether a thread in the given apartment gets an object of the class.
bool Creates(REFCLSID clsid, REFIID iid, DWORD apartment) {
  bool made = false;
  std::thread([&] {
    ::CoInitializeEx(nullptr, apartment);
    IUnknown* object = nullptr;
    const HRESULT hr = ::CoCreateInstance(clsid, nullptr, CLSCTX_ALL, iid,
                                          reinterpret_cast<void**>(&object));
    made = SUCCEEDED(hr) && object != nullptr;
    if (object != nullptr) object->Release();
    ::CoUninitialize();
  }).join();
  return made;
}

bool CreatesDmo(DWORD apartment) {
  return Creates(CLSID_CWMAudioAEC, __uuidof(IMediaObject), apartment);
}

}  // namespace

int main() {
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  if (!CreatesDmo(COINIT_MULTITHREADED)) {
    std::printf("SKIP: this Windows has no Voice Capture DMO\n");
    return 0;
  }

  CHECK(KeepWebRtcEchoCanceller(), "registering the refusing factory");
  CHECK(KeepWebRtcEchoCanceller(), "a second call");
  CHECK(!CreatesDmo(COINIT_MULTITHREADED), "an MTA thread still got the DMO");
  CHECK(!CreatesDmo(COINIT_APARTMENTTHREADED),
        "another STA thread still got the DMO");
  {
    IUnknown* object = nullptr;
    const HRESULT hr =
        ::CoCreateInstance(CLSID_CWMAudioAEC, nullptr, CLSCTX_INPROC_SERVER,
                           __uuidof(IMediaObject), reinterpret_cast<void**>(&object));
    CHECK(FAILED(hr) && object == nullptr, "the main thread still got the DMO");
    if (object != nullptr) object->Release();
  }
  CHECK(Creates(__uuidof(MMDeviceEnumerator), __uuidof(IMMDeviceEnumerator),
                COINIT_MULTITHREADED),
        "other classes must be untouched");

  ReleaseWebRtcEchoCanceller();
  CHECK(CreatesDmo(COINIT_MULTITHREADED), "released, the DMO is back");

  ::CoUninitialize();
  if (failures) {
    std::printf("%d failure(s)\n", failures);
    return 1;
  }
  std::printf("PASS\n");
  return 0;
}
