# FFmpeg, patched

FFmpeg 9.0.2 (LGPL-2.1-or-later as Rift builds it), from
`https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz`. Its signature was checked
against FFmpeg's release key (`FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676
58D8`) on Oct 9 2026, and `native/ffenc/build.sh` checks the tarball's sha256
before every build. Only the patches are kept here; the build downloads the
rest.

Built with everything off but `libavcodec`, `libavutil` and the GPU encoders,
statically, where every FFmpeg symbol stays hidden: LiveKit's libwebrtc
carries Chromium's FFmpeg under the same names. On Linux that is
`librift_ffenc.so` (`native/ffenc`) with the VAAPI encoder; on Windows,
`rift_ffenc.dll` with the NVENC, Quick Sync and AMF encoders, built with
MSYS2's MinGW against NVIDIA's codec headers (nv-codec-headers n11.1.5.4, for
drivers from 471.41), AMD's AMF headers (1.5.2, the oldest FFmpeg 9 takes)
and Intel's libvpl dispatcher (2.17.0), each pinned by sha256 in
`native/ffenc/build.sh`. libvpl's stand-ins for old MSVC's string functions
break MinGW's headers, so the build narrows their guard to MSVC with `sed`
rather than carrying a patch for one line.

Every patch applies to both builds; each touches only encoders one of them
builds.

## `vaapi-encode-moving-bitrate.patch`

FFmpeg's VAAPI encoder works out its rate control once, when it opens, and
sends it to the driver only with a keyframe. WebRTC moves a share's bitrate
every few seconds as its estimate of the link moves, and Rift passes each move
on (`rust/src/screenshare/encoder/ffmpeg.rs`). Without the patch the encoder
stays at the rate it opened at, which on a slow link is the picture falling
behind the sound (`rust/src/screenshare/rate_gate.rs` would then leave out
pictures to make up for it).

The patch notes the bitrate and maxrate the rate control was worked out from.
When the caller has moved either before a picture, it works the rate control
out again the way opening does, keeping the HRD buffer's length in time, and
sends it with that picture, so the next keyframe needs nothing extra.

Measured Oct 9 2026 on Intel's Alder Lake (iHD 26.2.4), 720p60 noise, with the
rate moved 8 → 2 → 6 Mbps and a keyframe forced at 2: patched, each second
after the first came out within 5% of its target, but for the one with the
keyframe (2.27 of 2 Mbps); without the patch, every second came out at 8 Mbps,
through the keyframe too.

Measured Oct 9 2026 on AMD's RX 9070 XT (Mesa 26.2.4), 1440p60, with the rate
moved 20 → 5 → 12 Mbps: each second after the first came out between 6% under
and 15% over its target, with no spike in the second the rate fell.

## `nvenc-moving-bitrate-without-keyframe.patch`

FFmpeg's NVENC encoder does pass a moved bitrate on, between two pictures, but
it resets the encoder and forces an IDR to do it. WebRTC moves a share's rate
every few seconds, so every move became a keyframe: a burst of bits on a link
that has just said it can carry fewer. NVENC takes a new average, peak and VBV
buffer without either when the GPU reports
`NV_ENC_CAPS_SUPPORT_DYN_BITRATE_CHANGE`, which FFmpeg already checks before it
reconfigures, so the patch drops the reset and the IDR.

Measured Oct 9 2026 on an RTX 3070 Ti Laptop (driver 610.74), 1440p60 noise,
with the rate moved 20 → 5 → 12 Mbps and a keyframe asked for at 7 s:
unpatched, a keyframe at each move, and 5.66 and 13.90 Mbps in the seconds the
rate moved; patched, keyframes only at the start and where asked, 4.98 in the
second the rate fell and 5.2 to 5.4 after, and the climb to 12 took three
seconds (9.2, 10.7, 11.8).

## `amf-encode-moving-bitrate.patch`

FFmpeg's AMF encoder sets the target, peak and VBV buffer once, when it opens,
and never looks at them again, so it would stay at its opening rate whatever
WebRTC asked for. AMF takes all three as dynamic properties, so the patch notes
what it last sent and, when the caller has moved any of them, sets them on the
encoder before the next picture goes in, with no keyframe.

**Not yet measured**: there was no AMD GPU to run it on. Rift leaves AMD's GPUs
to Media Foundation until it has been (`rust/src/screenshare/encoder/ffmpeg.rs`).

## Quick Sync needs no patch, but its settings matter

FFmpeg's Quick Sync encoder passes a moved rate on by resetting the encoder. On
an Iris Xe (Alder Lake, driver 31.0.101.4502, Oct 9 2026) the reset was refused
("incompatible video parameters") whenever the VBV buffer moved with the rate,
and with the buffer held, every reset started a new sequence with a keyframe
while HRD conformance was on. So `native/ffenc/ffenc.c` opens Quick Sync with
the buffer at one second of the most the rate will reach, never moves it, and
turns HRD conformance off. FFmpeg also sizes Quick Sync's output from that
buffer once, when it opens, so a buffer sized for the opening rate could leave
no room for a keyframe later. Measured as for NVENC: 19.6 to 20.0 Mbps at 20,
7.2 in the second it fell to 5 and 4.7 to 5.3 after, 11.5 to 12.8 at 12, and
no keyframe at any move.
