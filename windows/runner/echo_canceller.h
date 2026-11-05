#ifndef RUNNER_ECHO_CANCELLER_H_
#define RUNNER_ECHO_CANCELLER_H_

// Keeps libwebrtc on its own echo canceller on Windows.
//
// With echo cancellation on, libwebrtc's Windows audio device asks for the
// system's Voice Capture DMO (CLSID_CWMAudioAEC) when it is created, and when
// one is there it records through it and turns its own canceller off. The DMO
// records 16 kHz mono, so the audio processing module runs at 16 kHz, and so
// does its copy of everything the call plays (CALLS.md, "How a call is played
// out on the desktop"): a call heard on Windows was cut just under 8 kHz, and
// every Windows microphone was sent at 16 kHz. Measured Nov 5 2026 in the VM,
// a stereo test sound shared from Linux: 7.5 kHz with echo cancellation on,
// 15.0 kHz with it off.
//
// libwebrtc has no switch for this, so the DMO's class is registered in this
// process with a factory that refuses to make one. The audio device then
// finds none and libwebrtc cancels echo itself, at 48 kHz, as it does on
// Linux. The registration is visible to every apartment, since the audio
// device is made on a thread of libwebrtc's. Nothing else in Rift uses the
// DMO. If registering fails, the DMO is used as before.

// Call once on the main thread, after COM is initialised and before any
// plugin runs. Returns whether the block is in place.
bool KeepWebRtcEchoCanceller();

// Call before COM is uninitialised.
void ReleaseWebRtcEchoCanceller();

#endif  // RUNNER_ECHO_CANCELLER_H_
