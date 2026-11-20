#ifndef RIFT_CALL_CLIP_CALL_CLIP_H_
#define RIFT_CALL_CLIP_CALL_CLIP_H_

#include <stdint.h>

#if defined(_WIN32)
#define RIFT_CALL_CLIP_EXPORT extern "C" __declspec(dllexport)
#else
#define RIFT_CALL_CLIP_EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace rift {

// Puts a tap on what the call plays (libwebrtc's render pre-processing),
// which keeps the last stretch of it for clips while Dart has clipping on
// (CALLS.md, "Clipping a call"). Call once, beside InstallNoiseFilter.
// Returns false, and clipping stays unavailable, when there is no factory.
bool InstallCallClip();

// The microphone as the call hears it, from the noise filter after its
// processing: a 10 ms mono block at `rate`. Kept only when Dart asked for
// the mic to be in clips.
void CallClipMic(const float* mono, int frames, int rate);

}  // namespace rift

// Looked up by Dart through dart:ffi in the executable (CallClipNative).

// 1 when InstallCallClip succeeded.
RIFT_CALL_CLIP_EXPORT int32_t rift_call_clip_available(void);

// How much to keep: `seconds` of the call (0 frees it all), and the mic beside
// it when include_mic is 1. A shorter length keeps the newest audio.
RIFT_CALL_CLIP_EXPORT void rift_call_clip_configure(int32_t seconds,
                                                    int32_t include_mic);

// 1 keeps blocks from the next 10 ms, 0 stops (Rift rejoining). Dart turns it
// on only once the call has been told that clipping is on.
RIFT_CALL_CLIP_EXPORT void rift_call_clip_set_writing(int32_t on);

// Frames a snapshot would hold now, at 48 kHz.
RIFT_CALL_CLIP_EXPORT int64_t rift_call_clip_frames(void);

// Copies up to max_frames of the newest audio to `out`, interleaved 48 kHz
// stereo 16-bit, the mic mixed in when kept. Returns the frames written.
RIFT_CALL_CLIP_EXPORT int64_t rift_call_clip_snapshot(int16_t* out,
                                                      int64_t max_frames);

// The rate and channels libwebrtc last played the call at, for the log; 0 and
// 0 before it has played anything.
RIFT_CALL_CLIP_EXPORT void rift_call_clip_format(int32_t* rate,
                                                 int32_t* channels);

#endif  // RIFT_CALL_CLIP_CALL_CLIP_H_
