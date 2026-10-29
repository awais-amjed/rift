# Calls in depth

How voice, video and screen sharing work underneath, with the measurements and
the bugs behind each choice. `ARCHITECTURE.md` §5 is the overview — what a call
is, who holds its key, what the server can see — and this is the detail it
leaves out. Headings match the ones cited from the code.

## A stream is part of being in the call

A share is a connection of its own, so it does not go where the call goes, and
the app holds the two together from both ends. The sharer's app follows every change of its call in one
place (`LiveKitCubit.onChange`, `LiveKitState.leftCall`) rather than at each way
out, and a share that finishes starting after its call has gone ends at once.
Everybody else's app leaves out, and silences, any share whose owner's connection
is not in the room (`sharesWithoutOwner`), whatever the sharer's app did, and
brings it back when the owner is. A region change or a rejoin puts the call in a
new room, so after every join the share follows it (`ScreenshareCubit.followCall`): on a desktop its connection is
replaced and the picture published again, keeping the capture, so a Wayland
portal is not asked a second time; a shared app's sound is started again; on the
web and on a phone, where a share can start only from a click or fresh consent,
it ends and the sharer is told. A share left in another call ends, and so does
one whose call failed to come back: it can reconnect with the token it holds
when the call cannot get a new one, and would stream on to a room the sharer is
not in. Viewers keep
watching a stream that drops out and is back within half a minute
(`WatchResume`), whoever's connection it was that dropped.

## A call belongs to its server, not to the selection

A call carries on while its member reads another server, so the call keeps its own
(`LiveKitState.currentServerId`), and everything it asks a server for names
that one: a rejoin's token, a share's, the key it loads and the rotations,
heals and bot seals that follow (`ChannelKeyring` keeps the server it loaded
from). A join that starts from a channel finds the server listing it
(`SessionRepository.serverWithChannel`), since a moderator's move or a resumed
call can arrive while another server is open. Following the selection was a
real bug: the call's key work went to the server being read, failed there, and
the call stayed on a key the rest of the room had rotated off — connected,
with no sound and no streams.

The same holds for what the call draws and plays, and for where it is seen.
`SessionRepository.callServer` names the call's server (published by
`LiveKitCubit`). What the app keeps live about a server — its roster,
presence, soundboard, voice listeners, reports and doorbell — is that server's
`ServerContext`, and `ServerHub` holds the call's server's context for as long
as the call lasts, beside the selected server's. So the call's tiles read the
call's roster for faces and names, and the call reads it to tell its bots
apart, whose key is a different one; a press is played from the call's
server's library; and our presence entry and voice location stay on the call's
server while another is open, since its presence cubit is alive. A context
nothing holds is shut at once. The call's surfaces sit under the call's
server's scope (`CallServerScope`), which its menus, profile and full-screen
stream carry with them, so a right-click on a tile moderates, moves, reports
and messages on the call's server. Every call to a server is bound to the server it
names (`ServerSession`); none falls back on the selection, so a surface that
forgets to name one fails to compile rather than acting on the server being
read. Before this, opening another server mid-call
turned every face in the call into a generated one, silenced the call's
soundboard, and showed everybody still on the call's server that the member
had left a call they were still talking in. Verified Oct 18 2026 with three web
clients on the local stack (`TESTING.md`).

Nothing below the server list reads the selection but `ServerHub`. The open
channel and the server DM list are the selected server's because the hub tells
them when it moves; each keeps the server it was told, and a channel opens on
the server the click names. So a send, a key sweep or a DM read begun on one
server finishes on it, and which server notifications count as "open" is the
one the chat and the DMs say they are on rather than whichever is selected by
the time they ask.

## Hiding your voice from somebody — [Implemented October 2026]

"Hide my voice from them" is the other direction from a mute for yourself:
they stop hearing you, in every call, until you take it back. It is this
device's setting, kept like a mute for yourself (`AppState.voiceHiddenFrom`), and
nobody is told, not even them.

**The SFU enforces it, not their app.** Your app tells LiveKit who may subscribe
to your tracks (`VoicePrivacy`), and the server sends your microphone to nobody
else, so a modified app hears no more than a stock one. LiveKit has no "everyone
but these", so once anybody is hidden the call runs on an allow-list: everyone
present is named, a hidden person with every track of yours except the
microphone, and all of their connections (each device, each share) are covered,
since the list goes by user id. Somebody who joins later hears you once your app
has named them, about a fifth of a second after they arrive. A track you publish
is named only by the next list, which never names the microphone. While anybody
is hidden, the microphone is not published inside the connect: it waits until
the first list has gone, or it would reach everyone present before the list
could. Verified Oct 14 with the Linux app against a local LiveKit and scripted
listeners (`TESTING.md`): the hidden person, and their second device, received
nothing, including across a rejoin; somebody arriving later got the mic as they
joined; hiding mid-call cut them within a second; and un-hiding reconnected them.

A **full reconnect** is a new session on the server, which lets everybody
subscribe until told otherwise, and LiveKit publishes the microphone again
before the app hears the call is back. So while anybody is hidden, the
microphone sends silence from the moment the call drops until the list has been
sent for the new session. A hidden person may be subscribed for that moment, but
only to silence. Verified Oct 14 with three forced full reconnects
(`sendSimulateScenario`) while speech played into the test mic: the hidden
person was never subscribed, and everyone else had speech again within a
quarter of a second.

What it does not hide: they still see you in the call, and your speaking ring,
which comes from the server's active-speaker reports (*Speaking indicator*).
They also hold the room key, so it rests on whoever runs the server's LiveKit
forwarding as told.

**Everyone but one, for one call.** A participant's menu also offers "Hide my
voice from others", which is the same allow-list with everybody hidden but
that person (`LiveKitState.voiceOnlyFor`, `VoicePrivacy`'s `onlyTo`), bots
included; somebody hidden in every call stays hidden even if they are the one.
Its counterpart for listening is "Mute everyone else for me"
(`LiveKitState.listeningOnlyTo`): everyone else's voice, shares and soundboard
clips are held here the way a deafen holds them (`hearsRemoteAudio`), leaving
each person's own mute and volume as they were, and the one person's own mute
comes off. Both last for the call they were set in: a rejoin of it keeps them,
and leaving or moving to another channel drops them. Verified Oct 24 2026 with
two Linux debug clients on the local stack (`TESTING.md`).

## What a share sends, and to whom — [Implemented October 2026]

A viewer receives a share only after pressing Watch, so most shares spend
time with nobody watching. The share's connection turns on LiveKit's
**dynacast**: the server tells the sharer to stop sending a picture nobody
receives, and libwebrtc stops encoding it (a GPU share's encoder carries on,
and WebRTC drops its frames). It pauses about 10 s after the last
viewer goes. The next viewer's first picture comes within a second. Calls had
it already, for cameras.

A share sends **one picture**, not simulcast's two or three sizes. Tried Oct
6 2026: on VP8 a second, half-size picture let a viewer on 2.5 Mbps watch at
30 fps where one picture gave them nothing, and stopped their requests for a
fresh picture costing everybody else full frames. But it does not reach what
Auto picks. libwebrtc turns VP9 simulcast into layers inside one stream and
holds it to its camera bitrates: a share set to 6 Mbps sent 2. Real VP9
simulcast needs a setting LiveKit's Rust SDK does not expose. And the path
the GPU's H264 goes through carries one picture.

## Watching while Rift cannot be seen — [Implemented October 2026]

A watched stream's picture is turned off while nobody can see Rift: minimised,
hidden to the tray, or covered by another app's window (`_PicturePauseMixin`).
The video publication is disabled, as a deafen disables a voice, so the server
stops sending it and there is nothing to decode or draw. The stream stays
watched: its sound plays on, and the watching attribute is left alone, so the
sharer and the others still see you watching. Once Rift can be seen again the
publication is handed back to adaptive stream (`clearEnabled`,
`third_party/livekit_client/RIFT_PATCHES.md` patch 4); `enable()` would keep it
on for good, drawn anywhere or not. With this client the only viewer, the
server then has nobody to send the picture to, as when nobody watches
(dynacast, above); the sharer's side of that was not read.

A picture that arrives while Rift cannot be seen starts off as well. One does:
a stream that drops out and comes back within `WatchResume`'s 30 s is watched
again by itself, minimised or not. LiveKit's server (1.13) turns a disabled
track back on when it binds it under adaptive stream, so that the client says
what it can see again (`SubscribedTrack.Bound`), and the SDK's `disable()` does
not say anything twice. So such a picture played on unseen until Rift was
restored. The SDK now says it again when the server reports the track sending
(`third_party/livekit_client/RIFT_PATCHES.md` patch 5).

On Windows every decoded frame redraws the whole window, on screen or not. The
engine converts each frame to RGBA on the CPU and uploads it on the raster
thread, so watching a 1080p60 stream cost a laptop 117% of a core in front, 122%
minimised and 105–118% behind a maximised window.

**What counts as not seen.** `AppSeenListener` asks the app lifecycle: hidden,
paused or detached. On Windows the lifecycle never says it: with Dart on its own
thread, minimising and hiding the window changed nothing in it, only losing and
regaining the focus (inactive, resumed). The Windows runner says it instead
(`SeenWatch`, `rift/window_seen`). It reports minimised or hidden, and covered:
the foreground window belongs to another app, is above Rift in the order windows
are drawn, and covers all of Rift that is on screen. The desktop, a click-through
or see-through overlay and a cloaked window cover nothing. It looks again when
the foreground changes, when any window finishes moving or sizing or is
minimised or restored (WinEvent hooks), when Rift's own window moves, shows,
hides or changes place in that order, and once a second while another app is in
front or Rift cannot be seen. A game going fullscreen after it took the
foreground is caught by that last check. Rift partly covered, or beside a
fullscreen window on another monitor, keeps its pictures. So does a phone's
floating window.

Measured Oct 26 2026 on a laptop's Windows (Core i7-12700H, Iris Xe), watching
a CS2 share at 1080p60 in H264, in % of one core, with frames drawn a second
(the performance kit's results, on the `watch-draw` branch):

| | Before | After |
|---|---|---|
| Watching, in front | 117%, 52 | 121%, 52 |
| Minimised | 122%, 59 | 13%, 5 |
| Behind a maximised window | 105%, 47 | 13%, 5 |
| Behind a stand-in game in a maximised terminal | 116–118% | 19–20% |

In the call and not watching it was 8%, and 3 frames a second. Beside the
stand-in game, its frames taking over 1.5 times its fastest went from
1.57–1.70% to 0.22–0.28%. With Rift closed it was 0.07–0.09%. Received data
fell to about 25 kbit/s, the call's voices. The picture was back 97–186 ms after
Rift could be seen, in nine restores, uncovers and shows from hidden after
13–35 s away, and about 0.2 s after 6 minutes minimised. Seven Alt+Tabs in a
row each switched it. The sharer leaving and rejoining within 30 s while Rift
was minimised left it at 4 frames a second and about 20 kbit/s, against 38 and
3.5–4 Mbit/s before patch 5, and the picture was back 255 ms after a restore.
Not yet measured on a phone, where the background is paused.

**On Linux, X11 has the lifecycle, and Wayland the runner.** Under X11 GTK
reports a window minimised or hidden by Rift itself (the title bar's close, to
the tray), and Flutter's Linux embedder turns that into `hidden`. Measured Oct
26 2026 on the same laptop under X11, watching a 1080p60 H264 share: 52% of a
core in front, 9% minimised and 10% hidden to the tray, against 27% minimised
before (the decoder alone, since GTK stops drawing a minimised X11 window). The
picture was back on restore and on a second launch showing the hidden window. A
window unmapped by another program is not reported, and a covered X11 window
is still asked for frames, so covered is not detected there.

Under Wayland GTK 3 never hears minimised: xdg-shell has no such state, and the
suspended state GNOME sends instead is one GTK 3 does not read, so the
lifecycle stayed resumed and Rift went on receiving, decoding and drawing the
stream. The runner tells Dart instead, on the channel Windows uses
(`seen_watch.cc`), from what the compositor does: GNOME stops answering a
window's frame requests while it is minimised or wholly covered. The runner
asks for a frame on Rift's surface twice a second, repainting a pixel so that
an idle Rift commits one to carry the request; one unanswered for 1.5 s means
nobody can see Rift, and two answered close together that it can again (GNOME
lets a single frame through a few seconds after hiding a window). GTK's own
frame clock is no use for this: a window drawn with OpenGL, as Flutter's is,
ticks on at full rate while minimised. Measured Oct 26 2026 under GNOME 50 on
Wayland, the same share: 40–55% in front, about 10% minimised from Rift's own
button, 15% wholly covered by a maximised window and 8% in the tray, with the
decoder stopped in each; the picture was back on every restore. Other
compositors, another workspace and GNOME's own minimise keys were not tried.

## How Windows captures a screen — [Implemented October 2026]

libwebrtc captures a Windows screen or window with Windows Graphics Capture,
and Windows draws a yellow border round whatever is captured that way. From
build 20348, in practice Windows 11, an app may turn the border off, and
libwebrtc does. Windows 10 has no such option and no setting for it.

So on Windows 10 a **screen** is captured with DXGI desktop duplication
instead, falling back to GDI, neither of which draws a border
(`sources::options`, asked for Oct 24 2026 by a friend on Windows 10). Rift
asks Windows whether `GraphicsCaptureSession.IsBorderRequired` exists rather
than reading a build number. DXGI leaves the cursor out of its frames, so the
LiveKit fork draws it in (`set_wgc_screen_capturer`, `RIFT.md` there). A
screen's id differs between the two, so the list, its thumbnails and the
share all take their options from the same place.

A **window** keeps Windows Graphics Capture, and on Windows 10 its border.
The only borderless way to capture one there is GDI, which is slow and shows
most games black.

## Which sound goes with a shared window — [Implemented October 2026]

Windows records a window's sound by its process. Linux has no such tie: a
window is the desktop's, a sound is a PulseAudio stream. So a window share on
Linux finds the window's app, guesses its stream (`ShareSoundMatch`: the
window's process or one it started, then the app's id word by word, then a
player naming its track in the title), and asks the user to confirm in a popup
after the window is picked. The popup can **remember** the answer per app, and
the next share of that app's window skips it while that app is playing. No good
guess means every app but Rift, which still carries the window's sound.

Finding the app is where the platforms differ. X11 says it outright
(`_NET_WM_PID`, `WM_CLASS`), so the window is picked in Rift's own dialog.
Under Wayland the ScreenCast portal tells an app nothing about the window
picked, and libwebrtc runs that portal itself. On **GNOME and KDE** Rift runs
the picker first, asking for the pick to be kept (`persist_mode` 2): the
desktop then saves the window's app id and title in the PermissionStore under
the pick's restore token, Rift reads them, and libwebrtc is handed the token
(`select_restore_token`, a patch in our LiveKit fork) and opens the same
window with no second picker. GNOME saves a D-Bus structure; KDE saves a Qt
`QDataStream` (`KdeSavedPick`). GNOME deletes the saved pick once it is used
and KDE keeps it, so Rift deletes it after every share. Both ask as the same
app: GTK registers the app's own connection with the portal, so Rift's picker
registers its connection too, or the pick is saved for an unnamed app that
libwebrtc's request cannot see. Other Wayland desktops save nothing by
default; there the app picks the sound in the share dialog as before.

## Encoding a share on the GPU — [Implemented October 2026]

LiveKit's Rust SDK has no hardware video encoder on Windows: every frame of a
share was encoded in software on the same CPU a game is using. So on Windows
Rift encodes H264 itself and hands LiveKit the finished frames on its
pre-encoded path (`rust/src/screenshare/encoder/`): through **FFmpeg's GPU
encoders**, NVENC on NVIDIA's GPUs, AMF on AMD's and Quick Sync on Intel's,
from the same library as Linux's VAAPI below, tried in that order. Where none
opens, the share goes out as VP9. **Media Foundation**, Windows' own way to
the same encoders, was Rift's first encoder there and then AMD's fallback,
and was dropped on Oct 28 2026: NVIDIA's encoder through it crashed a 120 fps
share twice in two runs, and it runs past WebRTC's
target whenever the target is below what the picture costs: on a laptop's
Iris Xe and RTX 3070 Ti the rate gate had to leave out 200 to 1000 pictures
while WebRTC's estimate climbed at the start of a share (Oct 9 2026), and a
friend's 120 fps share on a 4070 Ti Super collapsed. FFmpeg's NVENC and Quick
Sync, on the same laptop, followed a rate moved from 20 to 5 to 12 Mbps
within a few percent, with no keyframe at a move, and so did FFmpeg's AMF on
an RX 9070 XT (Oct 11 2026), which left the rate gate under half of
Media Foundation's work there and held 98 to 116 fps on an upload capped at 8
to 30 Mbit where Media Foundation fell to 75 to 106. A PC with Intel graphics
beside an NVIDIA or AMD card gets the card's encoder, as on Linux; the
pictures reach the encoder from memory, so the GPU the screen is on does not
matter. Measured Oct 5 2026 through Media Foundation at 60 fps: 52
to 67% of a core, against VP9's 186 to 196% (`TESTING.md`).

On Linux an NVIDIA GPU is driven through **FFmpeg's NVENC encoder**, as on
Windows, and the frames go out on the same pre-encoded path. LiveKit has an
NVENC encoder too, but it is built from NVIDIA's Video Codec SDK samples, which
are under NVIDIA's licence and not one the GPL client can carry, so Rift's
build leaves it out (it only goes in when CUDA's headers are found, and the
release build has none). FFmpeg's reaches NVENC through nv-codec-headers: NVIDIA's
MIT-licensed API header and FFmpeg's loader, with the driver's libraries opened
at run time, the way OBS and Sunshine use NVENC. Measured Oct 16 2026 on an
RTX 3070 Ti Laptop: a moving 960x1000 window at 60 fps on 14% of a core, and
at 120 fps on 25% with nothing dropped (`TESTING.md`). Until then Rift drove
NVENC on Linux through the `shiguredo_nvcodec` crate; one encoder library for
both systems put the Windows fixes on Linux too: the
moved bitrate without a keyframe, the picture NVENC holds above 60 fps, the
colour tag. NVIDIA's encoder library waits on its threads for ever when the
process exits with an encoder open, so the library closes any still open at
exit (`ffenc.c`).

Intel's and AMD's GPUs on Linux are driven through **FFmpeg's VAAPI encoder**,
on the same pre-encoded path. LiveKit has a VAAPI encoder too, but on an AMD
RX 9070 XT (Mesa 26.2, Oct 9 2026) it stalled the viewer for 2 to 6 s every
8 to 25 s and made 34 of 60 frames a second; Rift's FFmpeg on the same GPU
was decoded at 56 of 60 and 115 of 120, one dip in two minutes. FFmpeg cannot be linked beside libwebrtc, which carries Chromium's
FFmpeg under the same symbol names, so it is built into a library of its own
(`native/ffenc`): FFmpeg 9.0.2 with nothing but `h264_nvenc` and `h264_vaapi`
on Linux (and `h264_nvenc`, `h264_qsv` and `h264_amf` on Windows), every
FFmpeg symbol hidden, opened by the Rust crate at run time
(`encoder/ffmpeg.rs`), and the first that opens an encoder is the one used:
NVENC, then VAAPI's render nodes in order. FFmpeg's VAAPI
encoder sends the bitrate to the GPU only with a keyframe, so the build patches
it to send WebRTC's every move with the next picture
(`third_party/ffmpeg/RIFT_PATCHES.md`); unpatched, an Intel GPU stayed at its
opening 8 Mbps while WebRTC asked for 2. It runs in variable bitrate capped at
the target, with the finest quantiser held at 18 as on Windows: in constant
bitrate Intel's GPU padded a still picture out to the full rate, and without
the floor it re-coded one at 4 Mbps of 20; a shared screen is mostly still.
FFmpeg's encoders, on both systems, say in the stream that its pictures are
BT.601 in limited range, which is how libyuv converts them (`ffenc.c`), so no
decoder guesses BT.709 for an HD picture and shifts its colours. Media
Foundation's fallback is left as it was, which leaves it to the decoder, whose
guess in libwebrtc is BT.601 anyway. NVENC comes first where both are
present. With neither, or without the library, H264 is not offered, and a
share asked for in H264 goes out as VP9.

A **Wayland share runs on Rift's own PipeWire stream** (`capture_pw.rs`, since
Oct 29 2026, on branch `gpu-codecs`): the ScreenCast portal from Rust (ashpd),
the stream in the same FFmpeg library (`native/ffenc/pipewire.c`, from OBS
Studio's), and each picture handed to VAAPI as the compositor's DMA-BUF, never
coming to the CPU. VP9 and NVENC get memory buffers instead, which the stream
switches to whenever the feed changes. Under Wayland VAAPI is tried before
NVENC for this reason. A window keeps Dart's pick (no second picker); a screen
is picked in the portal, and the first-picture limit starts once it answers. A
lent buffer keeps its own fds and mapping until Rust lets it go, since PipeWire
frees a stream's buffers on every renegotiation (a crash before that, Oct 29).
When the library, the portal or the stream refuses, libwebrtc's capturer runs
as before. Rift's portal connection registers as `com.codingfries.rift`, the id
GTK and Dart's picker use: unnamed, GNOME could not find the window Dart's
picker saved, and showed its picker a second time. The restore asks for the
pick to be kept while Rift runs (`persist_mode` 1), as libwebrtc's capturer
does: KDE ignores a restore asked not to persist and shows its picker again
(found Oct 30 in the KDE VM). GNOME closes the portal
session when a shared window closes and only pauses the stream, so the
session's `Closed` ends the share, as libwebrtc's capturer does; a minimised
window it keeps streaming live, so nothing shows paused there. A window's
memory picture is cropped, and goes to libyuv in whole rows. A compositor
sends a picture only when the window changes, where libwebrtc's capturer hands
over its last one on every tick: KDE drew a fully covered window once and then
nothing, and that one picture, which says the size the feed is made for, came
before the feed and was dropped, so the viewer saw LiveKit's black keepalive
(found Oct 30 in the KDE VM). So the last memory picture is kept, sent once the
feed is there, and sent again while nothing new comes, so a joining viewer's
keyframe has a picture to come from: every 100 ms for the first 2 s, then once
a second, the back-off libwebrtc's own still-screen mode makes (Oct 30), so a
still window is not encoded ten times a second. A viewer who joins a picture
still for longer waits up to a second for it. A DMA-BUF's is repeated by the
GPU encoder itself, and so is a memory picture that reaches it already the
encoded size, which is never converted to keep: the encoder's thread keeps the
NV12 it was given and encodes it again on a keyframe request and once a second
(NVENC takes every picture this way; found Oct 30 by the branch's review).
Proved Oct 29 by
the live share tests on GNOME 50 (Iris Xe): 1080p, a resize, a late joiner,
encoder failure to VP9 and no GPU; and in the app (the measurement and
what was driven are in `TESTING.md`).

- **H264 and AV1 are only ever encoded by the GPU or the OS, never by Rift.**
  The reason is patents: H264 is licensed through a pool the GPU makers belong
  to, so Rift ships no H264 encoder of its own (the FFmpeg it builds has only
  the encoders that drive a GPU's). VP8 and VP9 are royalty-free
  and stay as CPU codecs. Without a hardware encoder, or if one fails mid-share,
  the share goes out as VP9 and the user is told.
- **Auto, the default, picks the codec and the bitrate** (`ShareEncoding`):
  H264 where the GPU encodes it, VP9 where it does not or where sharpness was
  asked for, since it keeps text crisper at the same rate. The bitrate cap
  follows the picture's size and rate and the codec, with no ceiling of its
  own because it is only a cap (2K at 120 fps in H264 asks for 34 Mbps). The
  server's share limit holds it, like a chosen one, which can be up to 100.
  Either can still be picked by hand under the dialog's advanced settings.
- **Auto never drops to VP8 under load.** VP8 is the lighter codec only on an
  idle machine; on a busy one its encoder threads fight over the cores.
  Measured Oct 5 2026 on Linux (`bench_test.rs`, a moving 960x1000 window at
  60 fps): idle, VP8 took 43% of a core and VP9 67%; with every core busy,
  VP8 fell to 20 fps at 44 ms a frame while VP9 held 59 fps at 15 ms; pinned
  to one core, VP8 managed 4 fps. Under CPU pressure WebRTC already lowers
  the size or the rate, as the priority says.
- **120 fps is offered up to 2K, whatever encodes it**
  (`ScreenShareSettings.frameRatesAt`). WebRTC stops at 120, so there is no
  144. 4K at 120 is past what most viewers' hardware decoders take (H264's
  level 5.2 ends near 4K60), so it is never offered. A picture too big for
  120 goes out at 60, and the choice is kept for a smaller one. Whether the
  sharer's computer keeps up is the sharer's call. Measured Oct 6 2026
  (`bench_test.rs`, a moving window over X11, on a 20-thread laptop CPU):
  at 1920x1080 VP9 sent 119.8 fps at 147% of a core, 3.7 ms a frame; at
  2560x1440 VP9 sent 105 fps at 268%, 7.8 ms a frame against the 8.3 that
  120 allows, and the GPU's H264 112 fps at 86%. At 2K neither encoder was
  the limit: grabbing a window that size over X11 takes 7 to 9 ms. On
  Windows a share asks not to be power-throttled while it runs
  (`capture.rs`): Windows 11 slows a process it judges out of sight, as Rift
  is behind a game, and capture at 120 fell to about 92 pictures a second
  within seconds; unthrottled it held 119.8 (Oct 16 2026, a test process
  with no window, so the app's own case is inferred, not measured). FFmpeg's
  NVENC also holds one picture above 60 fps (`ffmpeg.rs`, `delay_frames`):
  waiting out each one at the idle clocks NVIDIA's driver drops to a few
  seconds into a share had kept it near 87 fps, and with it the viewer got
  118.7, at one more picture of delay (8 ms).
- **H265 is skipped**: too many viewers cannot play it.
- **AV1 is parked.** AMD's encoder makes AV1 that WebRTC carries, but no viewer
  gets it encrypted: LiveKit's Rust SDK does not negotiate what the server needs
  to find an encrypted AV1 keyframe, and its JS SDK refuses to encrypt AV1. The
  encoder keeps AV1, with a live test that says when that changes. The full
  notes, including the AV1 findings, are kept on the `gpu-encoding` branch.
- **GPU H264 goes out as constrained baseline.** High is built and tested
  but off (below): at a share's own rate it buys little, and every desktop
  viewer pays for it on the CPU.
- **What LiveKit's encryption leaves readable has to be enough.** Its frame
  cryptor leaves an H264 frame's bytes up to the first slice in the clear and
  authenticates them, plus that slice's NAL header and the byte after it, and
  a receiver reads two things from there: the start codes, which it rebuilds
  in the four-byte form (`h264::with_long_start_codes`, Oct 4 2026), and the
  IDR's PPS id. FFmpeg's VAAPI encoder wrote slice types whose bits pushed the
  id one bit into the ciphertext, so about one keyframe in two named a PPS
  that did not exist; whoever was watching dropped it and the pictures after,
  for up to a second each time somebody joined. The build patches it to the
  short slice types NVENC writes (`third_party/ffmpeg/RIFT_PATCHES.md`). On
  Windows Intel's runtime writes the header itself, as type 7, for Quick Sync,
  with no setting to change it, on Linux so does Mesa's encoder for AMD
  whatever FFmpeg hands it, and on Windows so does AMD's AMF. So a share
  rewrites such a keyframe's header before LiveKit sees it
  (`h264::with_readable_pps_id`): the short type, and `idr_pic_id` made as
  many bits longer, so the slice data stays where it was. Measured Oct 16
  2026 on an Iris Xe, a viewer joining every 4 s: before, the one already
  watching fell to 36 fps with 45 keyframes asked for in a minute; after,
  60.0 fps and none; on an RX 9070 XT at 1440p60, 42.0 fps with 46 asked
  for, then 59.8 and none. A share logs a warning if a keyframe still puts the id
  past the readable byte (`h264::idr_readable_when_encrypted`); the GPU live
  test fails on one.
- **A GPU encoder is held to WebRTC's target before it encodes, not after.**
  WebRTC's frame dropper is off for pre-encoded frames (`webrtc-sys` 0.3.49),
  since a dropped H264 frame breaks every frame after it until the next
  keyframe. That leaves whatever an encoder makes beyond the target — variable
  bitrate on a fast game, or a moment's lag behind a falling estimate — waiting
  in WebRTC's send queue, and on a link that cannot carry it the picture falls
  behind its sound. So `RateGate` (`rate_gate.rs`) counts what the encoder makes
  against the target and leaves pictures out on the way in once it is 0.2 s
  ahead: a slow link gets fewer frames, never late ones. Measured Oct 9 2026
  (`bench_test.rs`, Linux NVENC at 120 fps on a 10 Mbit upload, the encoder
  made to ignore the target): without it every packet waited 1.1 s in the
  queue, the link lost them and the viewer decoded nothing; with it nothing
  waited or was lost and the viewer got 36 fps. An encoder that follows the
  target lost 56 pictures in 30 s, as the estimate fell, and held 120 fps.
  A keyframe, made whenever a viewer joins or loses packets, can cost a few
  pictures' worth at once, and what the gate leaves out after it is left out
  for every viewer; its log line counts those apart. Measured Oct 16 2026 at
  1440p60 and 8 Mbps with a viewer joining every 4 s: on a still screen of
  text Intel's VAAPI made keyframes of about 300 KB and left out about 12
  pictures after each, NVENC on Linux about 110 KB and 1 to 6; on a moving
  picture keyframes were 50 to 65 KB and nothing was left out. Halving the
  encoder's buffer took VAAPI's 12 to about 6 but left the keyframe of text
  softer (29.6 against 30.5 dB), and a still screen is what text is shared
  on, where a picture left out changes nothing on screen. So the buffer stays
  at one second.

### H264 in High profile — [Implemented October 2026, off since Oct 29]

A GPU share's H264 can go out in High profile instead of constrained
baseline: with no B-frames it adds CABAC and 8x8 transforms, which measured
12 to 20% less rate at the same quality on motion and about 30% on text
(Oct 19 2026, Intel VAAPI with `ffenc.c`'s settings, offline). Decoding it
costs a viewer's CPU 20 to 55% more.

It is off (`encoder::SEND_H264_HIGH`, Oct 29 2026). A share runs at the
rate its sharer picked, so High does not save upload; it can only sharpen
the picture at that rate, and at the default 15 Mbps for 1080p60 there was
little left to sharpen: NVENC sent the same in High as in baseline, at its
quality floor, and Quick Sync 10% less (Windows, Oct 28). Every desktop
viewer decodes on the CPU, and paid 33% more for the clip in High, 50% at
its full rate. Worth turning on again once desktop viewers decode on the GPU,
or for a share whose rate is tight. With it on, the encoder is asked for it (`EncoderSettings::h264_high`,
the library's `high`), and the track is published offering High alone
(`TrackPublishOptions::h264_high`, a patch in our LiveKit fork, its
`RIFT.md`), because the server answers in its own order, which puts
constrained baseline first. Getting LiveKit's SDK to send it at all took
three changes there, each found by a share that sent nothing.

What a viewer is told differs by connection. The server forwards the track
as High where it made the offer, as it does to the app's viewers, and under
constrained baseline's name where it did not, as to a Rust SDK viewer on one
connection; a decoder that plays High either way decodes it. Every viewer
tried does, Firefox included, though its WebRTC lists only baseline: on Oct 29
2026 Firefox 155 on Linux watched a High NVENC share on the web build, live at
about 60 fps, both through the system FFmpeg (its default there) and through
OpenH264 2.6 (`media.navigator.mediadatadecoder_h264_enabled` off, the
decoder it uses where there is no FFmpeg). Verified Oct 28 2026
with `live_gpu_h264_is_seen_with_the_key_and_by_nobody_else` on NVENC and
Intel VAAPI against livekit-server 1.13.7: the sharer negotiated `640032`
and sent an SPS of profile 100, every picture reached the viewer with the key
and none without it, and the baseline path still passed; the real-share test
resized, rejoined and fell back to VP9 in High. The app's own viewers played
a High share the same day: a Linux desktop, Chrome on the web, and an Android
phone (Exynos) on its hardware decoder, though that phone's WebRTC lists only
constrained baseline among its H264 decoders. Windows did the same on NVENC
and Quick Sync, sharing and watching, and a Windows Rift without the change
played a High share. AMD's AMF is not yet driven.

## How a call is played out on the desktop — [Implemented October 2026]

On the desktop, everything a call plays — voices, a share's sound, a bot —
passes through WebRTC's audio processing module on its way out, not around
it. The library flutter_webrtc ships always installs a render
pre-processor (an empty one unless set), and with one installed WebRTC plays
the module's own copy of the audio instead of the audio. That copy runs at the
module's processing rate, and on Linux that is the capture rate, 16 kHz until the
microphone has recorded something. Somebody who joined muted and stayed muted
heard the whole call cut off just under 8 kHz; one unmute was enough to bring
it to the module's 32 kHz, and that held after muting again.

`PlayoutWarmup` closes that gap: joining without transmitting, the client
sends the microphone from one peer connection to another inside the process
for half a second, which is enough for the module to learn the rate, and closes
both. Nothing leaves the app and the call does not see the microphone open.
Once per session, since the rate holds until the app quits. Measured Oct 10
2026 on Linux: muted from the start went from a 7.3 kHz cut-off to 14 kHz, the
same as having unmuted.

**Linux only.** Windows uses the same library and measured differently in the
VM: about 14 kHz joined muted and unmuted alike, while the warm-up took it to
7.4 kHz and made Windows turn other apps down — recording there opens a
communications stream, which is what Windows ducks for.

**Still true:** nothing above about 15 kHz survives. It comes from the
library, and fixing it means building it without the render pre-processor.
That was done and measured on Oct 12 2026 (the same stereo test sound, Linux:
15.0 kHz with the shipped library, 20.1 kHz without the pre-processor) and
left out: the gain is above most people's hearing, and it means building and
hosting WebRTC for every desktop platform. The copy keeps both channels: a
stereo share reached a Linux listener with each ear's tone 94 dB below the
other (earlier notes calling it mono had measured a mono sender). Web,
Android and macOS use other WebRTC builds and are not affected (not
measured).

## Receiving a call's audio — [Implemented October 2026]

**Audio this client should not hear is held, never unsubscribed.** Deafened,
nothing is heard; a stream's sound only while it is watched; a share whose
owner has left, not at all (`hearsRemoteAudio`). The rest is turned off on the
device and the server is told to stop sending it (`disable()`), but the
subscription stays (`_AudioReceptionMixin`). Only your own share is dropped,
for good. A stream's picture is still unsubscribed while unwatched, so that
adaptive streaming keeps pausing the ones on screen nobody can see.

**A joining client drops unwatched pictures twice.** LiveKit's server
subscribes somebody joining to every track there is twice: when they join, and
again when their connection comes up ("participant active"), and the second
pass undoes an unsubscribe sent between the two. Often no track arrives at the
client to say so, so the SDK went on believing it had dropped the picture.
The stream was then downloaded and decoded, unwatched, until the call ended:
15 to 33 Mbit/s and a video decoder at up to 17% of a core on a laptop's
Windows. Watch asked for a track the server was already sending, so nothing
new arrived and the stage showed the sharer's avatar. A server restart, which
rejoins everyone, did the same to the sharer's own connection. So when this
client hears that it is active, it unsubscribes again from every picture it is
not watching (`_dropUnwatchedPictures`). The SDK sends that request even with
no track in hand (`third_party/livekit_client/RIFT_PATCHES.md`, patch 3).
Measured Oct 25 2026 on the local stack, from LiveKit's debug log: before the
change, about one rejoin in four while somebody shared left the stream
flowing; after it, none in sixteen, and the restart left it unsubscribed.

Unsubscribing is what turned calls to static. It hands the track's slot on the
subscriber connection back to LiveKit's server, which gives the slot to the
next track to arrive, and a slot keeps the id of the track it was first made
for. Subscribing to that first track again opens a second slot under the same
id, and flutter_webrtc fits each new track's frame cryptor to the *first* slot
with the id it is handed. The other slot is left without one and plays its
frames still encrypted: loud static on the stream, then on every voice that
passes through that slot — a push-to-talk member republishes on every press —
until the call is joined again. Watching, stopping and watching again, the
join-time drop of streams nobody watched, and deafening all did that. Reported
Oct 19 2026 after watching a stream on Windows and on Linux; reproduced Oct 21
on the local stack with LiveKit's Flutter SDK and bot members in 4 of 12 runs,
and in none of 12 holding instead (`TESTING.md`). The plugin's lookup is
unchanged upstream as of Oct 21 2026, and something other than this client can
still subscribe a track again (a member's voice hidden from you and shown
again). So each audio track's arrival also checks the subscriber connection
for two receivers under one id (`_checkReceivers`, desktop and phone; the web
fits a cryptor to the receiver itself) and joins the call again if it finds
them, at most once a minute. On the local stack the shared id was there about
fifteen seconds before the static, so the rejoin usually beats it. Pictures
sharing an id are only logged: they are still unsubscribed, so it can happen
often, and it costs one picture.

## Windows turning other apps down — [Implemented October 2026]

Windows lowers every other sound while an app has playback open through the
*communications* role ("ducking": 80% by default, set in the Sound window's
Communications tab). Measured Oct 10 2026 in a Windows 11 VM: such a stream
lowered a tone by 18 dB, the same speakers opened through the console role did
nothing, and a microphone alone did nothing. People notice it on their first
call and ask why their music went quiet.

Rift does not try to stop it. The setting is Windows', for every calling app,
and only takes effect when changed in that window (`WindowsSoundSettings`).
It says what happened instead. `rust/src/ducking.rs` registers for Windows'
duck notifications (`RegisterDuckNotification`, every session) and reads the
choice from the registry (`UserDuckingPreference`). A duck while the choice
lowers others puts "Did your other apps go quiet?" in the title bar during a Rift
call (`DuckingChip`) for a minute and a half (`DuckingCubit.hintFor`), then it
goes by itself; pressing it opens Settings → Voice & audio, scrolled to the
section and lit up. "Tell me when it happens" there turns it off
(`AppState.showDuckingHint`). It was a toast until Oct 24 2026, which was too
loud for a hint, and Windows reports a duck even when the person hears none (an
app may ignore it, or play on another device), so the toast also interrupted
people for nothing. The section shows the choice live, re-read when
the window regains focus, and draws Windows' four options with the one to pick
marked. **A change applies from the next call.** Windows keeps a duck until the
stream that caused it closes, so the section says to rejoin when the person
fixes it mid-call. With "Do nothing" set, Windows sends no duck at all.

## Speaking indicator

Encrypted frames cannot be measured by anyone without the key, but the level
travels beside them: each audio packet carries it in an RTP header extension the
frame encryption does not cover, so LiveKit's active-speaker detection works on
an encrypted call. Other people's indicators come from that. Your own is decided
on the device from the microphone's raw level, because the server reports only
the loudest few speakers on an interval and ordinary speech often never lit it.

## Rift beside a game — [Implemented October 2026]

People play while in a call, so on Windows what matters is not only how much
CPU a call takes but at what priority: a thread above a game's normal priority
takes a core from it whenever it wants one. libwebrtc gives each media queue its
priority, and by default it starts the queues that decode and hand on a received
video at `THREAD_PRIORITY_TIME_CRITICAL`, the highest a normal program can ask
for. The plugin turns on WebRTC's `WebRTC-MediaTaskQueuePriorities`, which gives
each queue one for its job instead: decoding and rendering a video above normal,
encoding the mic's Opus highest. Opus goes up, from normal; it takes a few
percent of a core, and a frame it is late with is a gap in your voice.

On Linux the same switch changes nothing: libwebrtc asks for real-time
scheduling, which an ordinary user is refused, so every queue stays at nice 0.

The mic's own thread is time-critical on Windows ("Pro Audio"), and libwebrtc
runs the noise model on it, so DPDFNet took its 2 to 8 ms of every 10 ahead of
a game. The model runs on a thread of its own at normal priority instead
(`rust/src/dpdfnet/handoff.rs`), sharing the cores with the game, and a frame
it is late with goes out unfiltered rather than hold the mic up. Measured Oct 25
2026 on a laptop's Windows, the model still on the mic's thread: with a
stand-in game on every CPU, the game's frames taking over 1.5 times its fastest
went from 0.16–0.31% with the filter off to 0.83–0.92% on DPDFNet-2, and its
99.9th percentile from 8.2 to 12.2 ms. With the model on its own thread
(measured the same day, the same laptop), CS2 limited mostly by the CPU ran
the same on DPDFNet-2 as with the filter off: 278–282 fps against 280–296, a
1% low of 100 against 99–107 and a 99.9th percentile of 10.5–10.7 ms against
10.1–10.9, with none of 34,025 frames of the voice late. The stand-in game,
which holds every CPU, still pays: 1.27–1.78% over 1.5 times and a 99.9th
percentile of 12.8–16.3 ms, with 1.8–2.5% of the voice sent unfiltered. One
step above normal sent none unfiltered, for the same cost to that game, and
was not tried in CS2. The model needs 30–40% of a core here, and a game that
holds every core loses it whichever thread runs it.

Measured Oct 25 2026 on a laptop's Windows: receiving a 1080p60 stream, the
decoder took 25% of a core at time-critical while a stand-in game ran on every
CPU, and the game's frames taking over 1.5 times its fastest went from 0.13% to
0.76%. In the Windows 11 VM, watching a stream, `VideoDecoderQueue` and
`IncomingVideoStreamQueue` read 15 before the switch and 1 (above normal) after
it, and `AudioEncoderQueue` 0 and then 2. Not yet measured: a game beside a
watched stream with the switch on.

Waking up costs a game too, even with nothing to do. Flutter now runs Dart on
the Windows main thread by default, and every Dart timer is then a delayed task
for the engine's `TimerThread`. That thread keeps firing once one task has
fired: a later time does not replace a time that has passed, so it fires at
once, wakes the main thread, is handed the later time again and drops it
again. Rift idle on a server woke its main thread and that timer 1,000 times a
second each in the Windows 11 VM (a laptop's own Windows showed 2,500–5,500,
not yet measured with the change); an empty Flutter app, with no timers, did
not. The runner puts Dart back on its own UI thread
(`UIThreadPolicy::RunOnSeparateThread`, `windows/runner/main.cpp`), where
Dart's timers never reach that thread. Found with a hook counting the main
thread's messages (all `WM_NULL` to `FlutterTaskRunnerWindow`) and who posted
them (the timer thread, 1,113 a second). The engine marks the policy for
removal, so it goes when the engine schedules a later time over a passed one,
or earlier if the policy goes first.

Measured Oct 25 2026 in the Windows 11 VM, Rift on a server with a call
running in its sidebar: the main thread woke 759–1,113 times a second idle and
1,746 in the call watching a stream; with Dart on its own thread 114–142 idle
and 172 in the call. A message notification showed and opened its channel
when clicked, typing and sending worked, and the call and the stream played.
