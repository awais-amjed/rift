# FFmpeg, patched

FFmpeg 9.0.2 (LGPL-2.1-or-later as Rift builds it), from
`https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz`. Its signature was checked
against FFmpeg's release key (`FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676
58D8`) on Oct 9 2026, and `native/ffenc/build.sh` checks the tarball's sha256
before every build. Only the patch is kept here; the build downloads the rest.

Built with everything off but `libavcodec`, `libavutil` and the VAAPI encoders,
statically, into `librift_ffenc.so` (`native/ffenc`), where every FFmpeg
symbol stays hidden: LiveKit's libwebrtc carries Chromium's FFmpeg under the
same names.

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
