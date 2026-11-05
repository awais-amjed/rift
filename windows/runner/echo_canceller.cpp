#include "echo_canceller.h"

#include <windows.h>

#include <objbase.h>
#include <wmcodecdsp.h>

namespace {

// A class object that never makes anything: the audio device takes the
// failure as "no built-in echo canceller". It lives as long as the process,
// so its count is not kept. Agile, as a class object registered with
// REGCLS_AGILE must be, since it is handed to other apartments unmarshalled.
class RefusingFactory final : public IClassFactory {
 public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** out) override {
    if (out == nullptr) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IClassFactory ||
        riid == IID_IAgileObject) {
      *out = static_cast<IClassFactory*>(this);
      return S_OK;
    }
    if (riid == IID_IMarshal && marshaler_ != nullptr) {
      return marshaler_->QueryInterface(riid, out);
    }
    *out = nullptr;
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return 2; }
  ULONG STDMETHODCALLTYPE Release() override { return 1; }

  HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown*, REFIID,
                                           void** out) override {
    if (out != nullptr) *out = nullptr;
    return CLASS_E_CLASSNOTAVAILABLE;
  }
  HRESULT STDMETHODCALLTYPE LockServer(BOOL) override { return S_OK; }

  // Made once, before the factory is registered and seen by any other thread.
  bool MakeAgile() {
    return marshaler_ != nullptr ||
           SUCCEEDED(::CoCreateFreeThreadedMarshaler(this, &marshaler_));
  }

 private:
  IUnknown* marshaler_ = nullptr;
};

RefusingFactory refusing_factory;
DWORD registration = 0;

}  // namespace

bool KeepWebRtcEchoCanceller() {
  if (registration != 0) return true;
  if (!refusing_factory.MakeAgile()) return false;
  const HRESULT hr = ::CoRegisterClassObject(
      CLSID_CWMAudioAEC, static_cast<IClassFactory*>(&refusing_factory),
      CLSCTX_INPROC_SERVER, REGCLS_MULTIPLEUSE | REGCLS_AGILE, &registration);
  if (FAILED(hr)) {
    registration = 0;
    return false;
  }
  return true;
}

void ReleaseWebRtcEchoCanceller() {
  if (registration == 0) return;
  ::CoRevokeClassObject(registration);
  registration = 0;
}
