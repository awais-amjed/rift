# Stepping a share down, and back up

Rewritten Nov 7 2026 for H265, when it was built. How it behaves is in `CALLS.md`,
*Stepping a share down*; this page keeps why, and what is still to prove. The first
design (Oct 29) is in this file's history.

## Why

H265 is sent at 11 Mbps where H264 High needs 12, for friends on slow connections,
but only a Rift desktop whose GPU decodes it can play it. Without this a browser, a
phone or an old Rift would get a black picture and no explanation.

One stream, never a second encode. LiveKit's backup codec was turned down on Oct 19:
a weak PC cannot afford a second encode.

## What was decided

- Automatic in every case, even H264 to VP9, which moves the encode to the CPU
  (about 1.5 cores at 1080p60) and may cost a game frames (owner, Oct 29).
- Someone in the call who is not watching must not pull the share down.
- Never above what the sharer picked. A hand-picked VP9 only ever drops to VP8.
- No `h264-high` rung. Firefox plays High though it lists only baseline, in the one
  browser tried, on Linux (Oct 29). Should one be found that refuses High, it comes
  back then.
- Dart decides, Rust moves. The move is the existing `updateScreenshare` with another
  codec, no new bridge call.
- The ladder is for desktop shares. Web sends VP8, which every viewer plays. Android
  sends what its dialog chose, relying on the SDK's VP8 backup (not tried).

## Calls made without the owner

- Phones and browsers do not say H265 at first, though the SM-A566B lists it.
- A watch connection that gives out takes H265 off the list until the next room, so a
  GPU failing on H265 does not bounce everyone's picture up and down. A brief network
  failure costs that viewer the same.
- Sharpness keeps Auto on VP9, as it was.
- After H265 falls back to H264 by failure, Auto's bitrate stays H265's until the
  next move (a rare case, and a republish to fix it would blink again).
- The sharer's own other devices count as watchers; only this device's preview does not.
- Note wording: "Sharing as H264 / So Sam can watch." and "Sharing as H265 again /
  Everyone watching can play it."
- A server with H265 off gets H264 with the failure's note, "H265 could not go out
  this time.", on each share, at Auto's H265 bitrate (11 Mbps, not 12) until a move.
  A rare setup, so neither is special-cased.

## Proved

Nov 7 2026, in the app on Linux (Intel VAAPI, a 720p window, local stack; `TESTING.md`):

- Desktop to desktop in H265 at 10 Mbps, Auto's rate then (11 since), decoded on the GPU
  through Rust.
- Someone in the call not watching changes nothing.
- A web watcher brings it to H264 at 12 Mbps at once, with the note; 30 s after they
  stop or leave it is back in H265, three times over.
- `RIFT_TEST_PLAYS` on a debug build's watcher: to VP9 at 10 Mbps, to VP8 at 13, and
  back up 30 s after. A hand-picked VP9 never climbs to H265.
- A server with H265 off: publishing does not fail, and no picture reaches anyone. The
  share now reads the join response's codec list (the fork's `RIFT.md`, item 7) and
  starts in H264.
- `live_gpu_watch_follows_a_share_changing_codec` moves a share between H265 and H264
  six times with a Rust watcher. The climb froze it until the watch connection stopped
  taking the old track's unsubscribe for the new one's.
- NVIDIA's decoder answer (`rift_ffdec_cuda_decodes`) says yes to H264 and H265 on the
  RTX 3070 Ti, in `test_ffdec` with GL on NVIDIA's node.
- NVENC's moves and CUDA in the app, with NVIDIA alone drawing the screen, driven
  Nov 7 2026 on a laptop in Discrete mode: a whole 1080p60 screen on Auto at 11 Mbps,
  Cara and Dave on Wayland, Eve on the web. Three cycles down to H264 at 12 and back
  30 s after Eve stopped. Dave's picture was back 0.94 to 0.99 s after a move down and
  0.39 to 0.46 s after a climb, going by the logs; Eve's by about 3 s. H264 picked by
  hand and VP9 picked by hand both played on CUDA.
- A client not decoding on the GPU no longer offers H265. The first run of the above
  had Cara under X11, where the share said H265, the server listed it as VP8 and
  nobody got a picture. Under X11 it now reads H264 at 12 Mbps and is seen. H265 from
  X11 itself stays off. It would need the fork's decoder factory to list H265.

- H265's cost beside a game: no more than H264 on NVENC. On Intel it took half the
  game's frames until the share moved to the low-power encoder, where it costs the
  same as H264 (`CALLS.md`, *Intel's low-power encoder*).

## To prove, in the app

- Why a first H265 share can start so low: 0.24 Mbps at 14 s, 1.4 Mbps at 80 s and
  9.8 Mbps after 5 minutes on NVIDIA, on a mostly still screen, and 0.24 Mbps once on
  Intel, where fresh H264 shares began at 4 to 5 Mbps. Too few runs to blame the codec.
- Intel's low-power encoder on older drivers, on GPUs before Alder Lake, on Arc, and
  on Meteor Lake and later, where it should reopen on the default entrypoint.
- Windows' Quick Sync beside a game: it may have the same cost, and `low_power` there
  is another option.
- A full-screen game at 1080p60, a phone viewer, and Windows, where a client without
  a GPU decoder should share in H264 as X11 does.
- A Firefox share at 1440p dropping to VP9: Firefox caps VP8 and VP9 at about 3.1
  megapixels (`max-fs`), so it may be refused or scaled.
