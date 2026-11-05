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

An H264 share with the GPU capture switch on, to NVENC or Quick Sync, now captures with
Rift's own Windows Graphics Capture session instead, on the encoder's GPU, so the picture
stays on the GPU (`capture_wgc.rs`, `docs/gpu-codecs/STEP1_WINDOWS.md`; on branch
`gpu-codecs` as of Nov 1 2026). AMF ran on an RX 9070 XT Nov 2–3 and passed, at about a fifth
of NVENC's cost to a game (`docs/gpu-codecs/STEP1_AMD.md`), and takes it too since Nov 4.
Until then it needed `RIFT_FFENC_AMF_TEXTURES=1`, held back by a late viewer's 3.5 s on it,
which was the viewer's wait (*Starting to watch through the call*). Everything else stays
as below, and Rift's session falls back to it. Verified Nov 1 with a test program on
NVENC: real shares with a viewer, the shared window closed 20 times (10
closed, 10 killed) with no crash or hang, and known colours within 0.5 of a level of
BT.601 limited. Driven in the app Nov 1–2 on NVENC (`TESTING.md`), CS2 among it. Quick Sync so far in ffenc's own test (`test_windows.sh`) and one bench
share with a viewer (58.3 fps decoded). A picture that fails to draw sends the last one again;
a second of them in a row, or the GPU gone, ends the encoder and the share goes on as VP9
(`live_wgc_failing_gpu_moves_to_vp9`), found within a tick even while no new picture
comes; a removed device hands the share to libwebrtc's capturer at once. A session that gives no picture for 2 s is
replaced by a new one on the same source, and again every 2 s while the new ones give
nothing; after five, the share goes to libwebrtc's capturer and stays H264 on the same
track (after one, 4 s, for a share that has had no picture yet, which would otherwise
give up waiting for one at 10 s). A hand-over after a game swapped its window goes on
with the window followed to, and a new window that will not open at once is tried again. A driver reset leaves Windows' session giving nothing, with no error, and the
viewer froze on the last picture for good; a capturer started a few seconds into the
reset fails at once, which is why the share waits out five. On a real reset (`dxcap
-forcetdr`, Nov 2) the pictures came back from the third new session, 6.6 s after they
stopped. A still source rarely trips this, since Windows also sends a picture whenever
the screen around it is drawn. The switch is *Capture the screen on the
GPU* in settings, shown on every Windows build: off, the next share never reaches Rift's
session, nor opens its device, and goes as below.

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

The picker is the desktop's window, so it does not hold Rift's Share button
down as Rift's own dialogs do, and it may go away without answering. A second
press of Share therefore takes over: it closes the first picker
(`org.freedesktop.portal.Request.Close`) and that attempt ends (`ShareAttempt`).
A picker nobody answers closes after 10 minutes, and the share is off. A press
does nothing while a share is starting or stopping, and a start that arrives
while a share runs leaves it alone. Before this, an attempt left waiting came
back after a newer share had started, opened the sound popup over it, and its
refusal marked the running share as failed: the bar offered Share screen again,
nothing could stop the share, and it went on sending past Leave. If Rust still
refuses a start as already sharing, the app shows that share as running, so
Stop reaches it.

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
coming to the CPU. Only a share whose encoder takes that DMA-BUF runs on this stream
(`takes_rifts_stream`): VP8, VP9 and an NVENC with no GL side go to libwebrtc's capturer, as with
the settings switch off, because on memory this stream stands still under a fullscreen window (below).
Except a VP8 or VP9 window on a screen NVIDIA's card draws alone, which comes here and reads
memory (Nov 2): libwebrtc's capturer reads GNOME's window DMA-BUFs with no wait on the
compositor, NVIDIA's driver does not make it wait, and the viewer saw black bands where the
window was not yet drawn (`STEP2_NVIDIA.md`, *A window in VP9*). Verified Nov 3 with two
clients: no band, and the window kept moving made fullscreen.
The cost is capture at about 12% of a core against 5%, beside VP9's own encoding at about 50%, and
no paused notice for a minimised window. A share whose GPU encoder fails partway goes out as VP9
and stays on the stream, on memory buffers, which it switches to whenever the feed changes. Both kinds are offered blue first
(BGRx, BGRA) and red first (RGBx, RGBA): some wlroots compositors share memory
only red first, and offered only the other order they could not share at all
(`ByteOrder`, which picks libyuv's conversion; Oct 30). Under Wayland VAAPI is tried before
NVENC for this reason, except on a **screen NVIDIA's card draws alone**: a card from NVIDIA
with a display connected and no Intel or AMD card with one (`gpu_choice.rs`). There NVENC comes
first and takes the DMA-BUF too (`native/ffenc/nvenc_gl.c`): imported into EGL, drawn
as NV12 by one GL shader pass, and copied by CUDA into NVENC's frame, on the worker's own
thread, with the compositor's explicit sync waited for on PipeWire's. Proved Oct 30 on an
RTX 3070 Ti, GNOME 50, with `test_nvenc_dmabuf.c` and a live share: 60 s of the whole screen
flipping between two grays gave no torn or stale picture (`STEP2_NVIDIA.md`, *Sync*), with
the sync timeline and without it, the GPU idle and full. While a fullscreen window fills that
screen GNOME sends a memory stream nothing, so a share there opens on DMA-BUFs (`first_buffers`).
Intel's screen is nearly the same (Oct 31): about one memory picture a second, enough for a VAAPI
share begun over such a window to learn its size and move to DMA-BUFs, not enough to watch, which is
why VP9 left the stream the same day: it stood still there and keeps going on libwebrtc's capturer.
A VP9 share falling back from a failed GPU encoder would still stand still under such a window. GNOME sends
that stream only on whole refreshes, and skips any refresh sooner than its cap allows, waiting for
the next: at most 60 on a 165 Hz screen gave every third, 55 fps, and at most 120 every second,
82 fps; asked for more, it clamps the cap to the screen's refresh, where a refresh that comes a
little early is skipped too (about 100 fps at 120). So Rift asks for twice the share's rate and
one more (121 at 60), and paces what comes itself, as on Windows (`pacer.rs`): a picture that
comes too early is held until it is due, or replaced by a newer one, never dropped, since a screen
that then stood still would show the one before. A screen faster than that cap gives at least half
of it, more than the share needs, and the compositor records no more than about the cap whatever
the screen (a 30 fps share of a 480 Hz screen would otherwise be 480 recordings a second). A screen
no faster has the cap cut to its refresh, even one at twice the rate exactly, and then Rift asks for
none (`maxFramerate` 0/1, which mutter takes as no cap at all), so 120 on the 165 Hz screen is
uncapped. Measured Nov 3 on the 165 Hz screen, NVENC
from NVIDIA's: the whole screen at 115–119 fps at 120 and 60 at 60, a 60 fps picture at 60, a
window at 60 (55, 54 and 46 asked for the rate, Oct 31). The gaps, by
`live_pw_stream_is_paced_to_the_rate` the same day: at 60, nine in ten within 16.6–16.7 ms; at 120,
the average right (589 pictures in 5 s) but nine in ten between 5.9 and 12.2 ms, one refresh or two,
since 165 does not divide into 120 and no pacing makes a picture between refreshes. KDE (Plasma 6.6.4
in the VM, a 75 Hz screen, Nov 3) keeps caps of 41 and 61, paced to 20 and 30 (101 and 151 in 5 s),
cuts one of 121 to its 74 and then takes none, paced to 60 (301), nine in ten within 0.8 ms of the
interval. What it costs (Nov 3, release builds, NVENC, a 165 fps picture on the screen, 3 × 20 s):
at 60, gnome-shell 26% of a core with the cap of 121 (about 81 recordings a second), 28–29% with no
cap (about 127) and 15–22% before (55), Rift 16% in each, and the GPU kept its full clock where
before it fell to about 400 MHz, NVENC's send then taking 9.8 ms a picture against 4.0; at 120,
gnome-shell 30–31% against 27–28%, Rift 23–24% against 18–19%, for 117 pictures a second against
82. Those runs had RustDesk recording the screen as well, a second screencast that more than doubles
gnome-shell's share and keeps NVIDIA's clock up: on Intel's screen at 120 (Hybrid, gears on the
screen, the same day) gnome-shell was 28–30% with it and 14% without, Rift 17% and 15%, NVIDIA's
card 39 W and 16–24 W, the share 120 a second either way. So the NVIDIA figures above are high
by RustDesk's part, and the full clock may be its. If the GL
side does not open, NVENC takes memory as before. A window keeps Dart's pick (no second picker); a screen
is picked in the portal, and the first-picture limit starts once it answers. A
lent buffer keeps its own fds and mapping until Rust lets it go, since PipeWire
frees a stream's buffers on every renegotiation (a crash before that, Oct 29).
When the library, the portal or the stream refuses, libwebrtc's capturer runs
as before. So it does when the person turns off *Capture the screen on the GPU* in settings,
from the next share (`ScreenShareConfig.gpu_capture`), for someone whose machine misbehaves. Rift's portal connection registers as `com.codingfries.rift`, the id
GTK and Dart's picker use: unnamed, GNOME could not find the window Dart's
picker saved, and showed its picker a second time. The restore asks for the
pick to be kept while Rift runs (`persist_mode` 1), as libwebrtc's capturer
does: KDE ignores a restore asked not to persist and shows its picker again
(found Oct 30 in the KDE VM). GNOME closes the portal
session when a shared window closes and only pauses the stream, so the
session's `Closed` ends the share, as libwebrtc's capturer does; a minimised
window it keeps streaming live, so nothing shows paused there. A pause is
told to viewers only once it has lasted a second, and through one task, so the
last word sent is the last one said: PipeWire pauses the stream for each
renegotiation too (about 20 ms on GNOME), and each one flashed "Paused" on
viewers' tiles, or left it there when the two words crossed (found Oct 30 by
the branch's review). A window's
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
The newest picture of either kind is kept until a GPU feed has taken it, and
offered again every 100 ms until one does: the rate gate can leave it out,
and a new encoder or track (a republish, a move to another room) has not had
it, and on a still screen nothing newer comes to take its place. The stream
lets Rust hold four pictures, and one that comes while Rust holds them waits
in the stream until Rust lets one go: handed back unseen, as OBS's rule had
it, a still screen's last change never reached the viewer (Oct 30).
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

## Starting to watch through the call — [Implemented November 2026]

A stream watched through the call's connection (the web, a phone, a desktop
where the Rust path is off or failed) is covered by loading dots until its
picture is clean (`DecryptedVideo`, `CleanPictureGate`). LiveKit's Flutter
SDK fits the receiver's decryptor only once the track is subscribed, by
which point frames are already arriving. The server asks the sharer for a
keyframe as the track is subscribed, so that keyframe usually goes through
the decoder still encrypted and decodes as garbage, and the frames after it
build on the garbage. The picture is clean only at the first keyframe after
decryption begins. A sharer sends no other keyframe unless one is asked
for, so the cover waited out its 3 s timeout nearly every time. That was
the late viewer's "about 3 s" on Linux, on Windows NVENC and on AMF from
textures: it depended on the viewer's path, not on the sharer's GPU.

So when decryption begins, the cover asks for a fresh keyframe
(`LiveKitCubit.renewPicture`). The SDK has no way to ask for one, but
LiveKit's server asks the sharer for a keyframe whenever a subscriber turns
a picture back on. So the picture is turned off for 300 ms and on again.
The server applies an "off" 100 ms after it arrives, and an "on" arriving
before then cancels it (`SubscribedTrack.UpdateSubscriberSettings`,
livekit-server 1.13), so the pause has to outlast that and the trip to the
server. The roster sync, which hands pictures back to adaptive stream, leaves
a picture alone while it is paused like this. Rift's log says when decryption
began, how many keyframes had decoded before it, and whether the cover came
down on a clean keyframe or on the timeout.

Verified Nov 4 2026 on the local stack. A Linux release build, Dave sharing,
Cara watching through the call (`RIFT_WATCH_PATH=call`), five watches. In
four, one keyframe had decoded before decryption began. The picture was
clean 0.68–1.3 s after Watch, about 0.6 s after decryption began, and
never on the timeout; the owner saw it come almost at once. In the fifth no
keyframe had gone by yet, and the picture came at 0.25 s. Not yet tried on
the web, a phone or Windows, which run the same code.

## Watching a share through Rust — [Built November 2026, Linux and Windows; `gpu-codecs` branch]

On a desktop, flutter_webrtc turned every decoded picture of a watched share
into RGBA on the CPU and uploaded that, which is most of what watching cost a
player (*Watching while Rift cannot be seen*, above). So on Linux a watched
share is received instead on a second, receive-only connection in Rust (the
*watch connection*, `rust/src/watching`), and the runner draws its pictures on
the GPU (`linux/runner/stream_texture.cc`): the three I420 planes of the
decoder's own buffer, lent to the runner when Flutter asks for a frame, are
uploaded as one-byte textures and turned into colour by a shader. Where the
GPU can, it decodes the picture too, and nothing of it comes to the CPU
(below). The design is in `docs/gpu-codecs/STEP3_PLAN.md`. On Windows the
runner draws the same planes with Direct3D 11 (`windows/runner/stream_texture.cpp`),
on a device of its own on the adapter Flutter draws with, waits for the GPU,
and hands Flutter the texture's shared handle, which ANGLE opens
(`docs/gpu-codecs/STEP3_WINDOWS.md`). Driven in the app Nov 4 (below); there
libwebrtc still decodes, on the CPU.

- **One connection per call,** `<user>~<device>_watch`, opened with the first
  share watched this way and closed with the last. The server mints it only
  while the device's voice connection is in the room (`get_channel_token`,
  `watch`). It subscribes to the watched shares' pictures and sound, by
  their sources (`Screenshare`, `ScreenshareAudio`), and nothing else: a
  phone shares on the connection it talks on, so its mic and camera sit
  beside the share, and taken by kind the mic played a second time over the
  call's copy (found by review Nov 5; `live_watch_takes_only_a_phones_share`).
- **Which way a share goes** is `LiveKitCubit`'s (`_RustWatchMixin`). A share
  goes through Rust when it can; otherwise it is received in the call's room,
  as before: on a build without stream textures (every platform but Linux
  and Windows, for now), with `RIFT_WATCH_PATH=call`, on a server whose answer to `watch`
  names the voice identity (one from before it, where joining with that would
  push this device's own voice connection out of the call, so it is not asked
  again that call), and after anything on the Rust path fails. Then the shares
  it held go back to the room and stay there, so a picture never changes paths
  twice, and the next share watched, or the same one watched again, tries Rust
  first: most failures end within milliseconds and belong to one share. The
  slow ones are the 6 s below and a connection that will not open. The room's
  own track for a share Rust holds stays unsubscribed.
- **The key:** the watch connection keeps the call's keys in a ring of its
  own: every version the call has held, given when it opens, since a share
  begun before a rotation stays sealed under the key it began with, and then
  each version the call moves to. Given only the current one, a watch opened
  after a rotation showed such a share as loading dots, with no sound and
  no error (found by review Nov 5). On Windows (Nov 5), a share begun on v1
  and watched after a ban moved the call to v2 showed through Rust at once,
  sound and all.
- **No picture:** a watched share subscribed and on for 6 s with nothing
  shown (`NO_PICTURE_WITHIN`) is taken as a loss, and the call's connection
  watches instead: a share this ring cannot read decrypts to nothing and says
  nothing (`live_watch_gives_up_on_a_share_it_cannot_read`).
- **Unseen:** its pictures are turned off and on with the call's
  (`setWatchPicturesOn`).
- **The sound** is played by Rust itself (`rust/src/watching/sound`), on a
  stream of its own on the output chosen in settings: PulseAudio's on Linux,
  and on Windows a WASAPI shared-mode stream, which counts its room from what
  the device still holds, as the mic test's playback does, and puts 30 ms of
  silence ahead when it ran dry. It holds about 30 ms on both once settled.
  The sound arrives on the system's clock and the output plays on its own, so
  `Drift` watches what the output holds and, when that wanders more than 8 ms
  from where it settled, stretches or squeezes a frame by one left-and-right
  pair. Before it, an output running fast left a 10 ms gap every 100 s or so at
  100 parts per million, and one running slow held more and more on Linux, so
  the sound fell further behind its picture, and on Windows had the ends of
  frames cut off. It is stereo and full band, where the call's playback ran a share's
  sound through libwebrtc's processing at 32 kHz (*How a call is played out
  on the desktop*, below). The cubit hands each share the volume the call
  would have played it at (`_syncRustSound`): its own volume times the
  call's, or nothing while it is muted, while deafened or while listening only
  to somebody else. At nothing the server stops sending it, as the call holds
  a sound nobody hears. The call's own copy is held all the while
  (`hearsRemoteAudio`, `playedElsewhere`), so it plays once. A player that
  cannot go on (an output that will not open, the sound server gone, three
  failed writes in a row on Windows) is a loss, and the call's connection
  takes the share back: a player that only stopped left the share silent
  with the call's copy still held (found by review Nov 5). Seen on Windows
  (Nov 5, laptop, local stack): an output another program held, and three
  write failures forced in a debug build (`RIFT_WATCH_SOUND_FAIL_AFTER`),
  each sent the share back within 2 ms, the tone going on through the call
  at −19.9 dBFS. The watch
  connection may unsubscribe a sound, which the call's must never do (*Receiving
  a call's audio*): this SDK gives a sound's decryptor the receiver itself,
  not an id two receivers can share. Where Rust has no player yet
  (`watchPlaysSound`: it has one on Linux and Windows for now), the sound
  stays with the call. Windows does not turn Rust's stream down beside Rift's own call,
  though it does other apps' (*Windows turning other apps down*): it spares
  the process whose call it is. Measured Nov 4 into VB-Cable made the
  communications device (`live_watched_sound_is_not_turned_down_beside_a_call`):
  a call's stream opened in the same process left the tone at −15.3 dBFS; the
  same stream from another process took it to −33.3, 18 dB down, and back
  once it closed. Windows ducks only the communications device's own
  streams: with the cable not that device, neither moved it. **The level
  matches the call's** (Nov 4, Hybrid, H264, the release app): a window
  playing a 1 kHz tone at −20.0 dBFS into VB-Cable was shared, and the
  watcher's own playback was recorded by its process (WASAPI process
  loopback), so the tone itself stayed out. Through the call −20.02 dBFS in
  each ear, through Rust −20.00, at full volume. Windows' Communications
  setting was at Do nothing, so this says nothing more about ducking.
- **Decoded on the GPU** where it can be (`rust/src/watching/decode`,
  Linux and Windows). At start (`init_app`), before any room, Rust chooses how the
  process's LiveKit runtime decodes: where Rift's FFmpeg library loads and
  GTK draws through EGL (Wayland), or on Windows where adapter 0 has a D3D11
  video decoder for H264 or VP9, the runtime decodes nothing (pass-through,
  from the LiveKit fork, `RIFT.md` there). Each watched share's picture is
  then read still encoded and decrypted, on a thread of its own, and decoded
  by FFmpeg on the GPU that draws the screen, by the rule sharing follows
  (`watch_decoder`): NVIDIA's only when it draws alone, else Intel's or
  AMD's (`native/ffenc/ffdec.h`). From Intel or AMD, through VAAPI, the
  surface leaves as two DMA-BUF layers, Y and interleaved UV, which the
  runner imports into EGL as two textures. From NVIDIA, through NVDEC on
  CUDA's primary context, the picture stays in CUDA's memory and the
  runner, with its GL context current, has the library copy it into two GL
  textures of its own (`rift_ffdec_copy_to_gl`, the way Moonlight does it),
  registered once and kept. Either way the shader reads Y and UV, in the
  matrix and range the stream says (BT.601, 709 or 2020, limited or full);
  libwebrtc's pictures are drawn BT.601 limited, as flutter_webrtc drew them.
  On Windows FFmpeg's D3D11 decoder runs on the runner's own device, the one
  it draws watched shares with on Flutter's adapter (the runner exports it,
  `rift_stream_d3d11_device`, so it never passes through Dart); each picture
  leaves as a slice of the decoder's texture array, which the runner's shader
  reads where it lies, or copies first where the driver will not let a
  shader read it. The device's multithread lock is FFmpeg's, and the runner
  holds it through each draw. VP8 is never decoded there: FFmpeg has no
  D3D11 decoder for it, so a VP8 share is watched through the call.
  The runtime is the process's, so the choice holds for the share
  connections too, which only send. A decoder starts at the stream's first
  keyframe and asks for one after a picture fails. A decoder 30 frames
  behind loses the backlog whole; the stream marks the frames after it
  (`after_gap`), and those wait for the keyframe asked for rather than
  decode against references thrown away, which smeared the picture (found
  by review Nov 5). On Windows (Nov 5, laptop, debug build, the
  decoder stalled 2 s by `RIFT_WATCH_DECODE_STALL_AT`): the stream flushed,
  the frames after it waited, logged, and a keyframe came within 0.5 s. A share the GPU cannot
  decode, three keyframes in a row that fail (on Windows the first picture
  that fails once the device it decodes on was removed, since none decodes
  on it again), a runner that cannot import
  (it says so when it makes the texture, `takesGpuPictures`), or a GPU
  picture the runner fails to import or copy (it hands it back undrawn,
  `rift_watch_frame_unlock`) sends the call back to watching through the
  call's connection. Elsewhere (X11, Windows without a decoder there,
  `RIFT_WATCH_DECODE=cpu`)
  libwebrtc decodes, as above. Rift's FFmpeg library carries the three
  decoders for it, through VAAPI and NVDEC, from 1.2 to 4.2 MB on Linux.
- **Receive stats from the watch connection.** A share Rust holds has no
  track in the call, so the badge and the stats card ask Rust
  (`watch_share_stats`) for libwebrtc's own counters for its picture, and
  the call's sampler turns them into rates as it does the call's. Decoded on
  the GPU they still count: the pass-through decoder hands libwebrtc a
  picture of the right size for each frame. Verified Nov 3 in Rust
  (`live_watch_`, `live_gpu_watch`): the size and codec sent and 30 pictures a
  second for 30 sent, through CUDA for VP8, VP9 and H264. Then in the app
  (Nov 3, two clients, NVIDIA): the badge and the stats card showed the
  share's numbers as they do through the call, for VP9, H264 and VP8 decoded
  through CUDA.

Verified Nov 2 against the local stack, in Rust alone (`cargo test
live_watch_`): a watched synthetic share arrives at its size and shade,
unwatching stops it, and a share sealed under a rotated key is read once the
key is added. The sound was verified the same way (`cargo test
live_watched_sound`, into a null sink, its monitor recorded): a tone sent at
−15.2 dBFS into one ear came out at −15.2 dBFS in that ear and nothing in the
other, silent at volume 0 and back when turned up, 6 dB down at half, and silent
once unwatched. On Windows the same test (Nov 4) plays into VB-Cable and
records the cable's other end itself: −15.2 dBFS in each ear for −15.3 sent,
nothing in the other, −21.3 at half, and silent at 0 and once unwatched; with
no player (`PLAYS` false) it fails. In the Windows app (Nov 4, release build,
two clients on the local stack on this laptop): the watcher's log shows the
runner's device on the Iris Xe, the share watched through Rust at 1920×1080
and its sound on the chosen output, the server the `_watch` connection
joining; the picture moved with the right colours, and the stats card read
60 a second of H264. A lost device, faked in a debug build
(`RIFT_STREAM_TEXTURE_FAIL_AFTER`), sent the share back to the call 30 ms
later, still moving. Decoding on the GPU in the Windows app (Nov 4, the same
laptop in Hybrid, release build): the watcher's log shows H264 and VP9
decoded on the Iris Xe through D3D11, whole screen at 1920×1080 and a window
at 946×1032, 60 a second on the stats card; a VP8 share came through the
call's connection instead, named in the log, 5 ms after the watch connection
gave it up. The owner saw H264 and VP9 move with the right colours, a whole
screen and a window, through resizes, minimising and restoring, leaving and
rejoining, and quitting from the tray while watching. With music shared from
the whole screen and the watcher's output on VB-Cable, recorded from the
cable's other end: −20 to −33 dBFS on average, −91 (silence) deafened or
with the stream muted, back on undeafen and unmute, and lower with the
stream's volume at 19%. A lost device faked while a decoder's picture was
lent sent the share to the call 27 ms later, still moving, and the next
watch made a new device and decoded on the GPU again. From the click on
Watch to the picture: 508–550 ms through Rust (the picture about 270 ms
after the watch connection found the share) and 266–773 ms through the call.
A device removed while only the decoder was using it went unnoticed by the
runner before (found by review Nov 5): a failing decoder hands nothing over
to draw, so it waited for three keyframes, and every later watch was made
on the dead device and went back to the call, until Rift restarted. Now the
runner asks the device whether it was removed whenever it is handed out, to
a new watch or to Rust's decoder (`stream_device.cpp`), and lets a removed
one go; the decoder gives up at its first failed picture once its device
says it was removed. Checked Nov 5 on the laptop's RTX in Discrete
(`windows/runner/test/run.ps1`): a D3D11 device over D3D12, removed alone by
`RemoveDevice` with no driver reset, was let go by the next watch and by the
export, each saying so once; a real reset was not run.
Then in the Linux app (Linux debug build, two clients on the local
stack, Nov 2): the watcher's log shows the share watched through Rust and the
picture arriving at each size the sharer's window took, up to 1920×1048; the
owner saw it move with the right colours in the tile and full size. Minimised
and restored twice, the pictures went off and on; Stop watching closed the watch
connection, watching again opened a new one, and leaving closed it. No fallback
to the call. The sound through Rust was then heard in the app the same way (Nov
2): left and right where they belong, starting as watching began, following the
stream's volume, mute, deafen, Stop watching, a share restarted mid-watch and a
change of output device mid-share. The
first try played nothing until the slider moved: nothing told Rust the volume
until the next roster change, so the cubit now syncs the sound the moment Rust
takes a share. Decoding on the GPU was verified Nov 2 the same ways: in Rust
alone (`cargo test live_gpu_watch`, Iris Xe), an encrypted VP8, VP9 and H264
share each decoded on the GPU at the size sent, 89 to 91 pictures in 3 s of
a 30-a-second share, so none lost; the decoder alone (`native/ffenc/test.sh`,
`test_ffdec`) gives back the four colours sent at 1920×1080, imported and
drawn the runner's way. Then in the app: Cara's log shows H264 and then VP9
decoded on the Iris Xe each time she watched, through two size changes and
the pictures turned off and on, and the owner saw both move with the right
colours and heard the sound. On NVIDIA drawing alone (RTX 3070 Ti laptop,
Nov 2) the same: `live_gpu_watch` decoded VP8, VP9 and H264 through CUDA, 89
to 90 pictures in 3 s each; `test_ffdec cuda` gave back the four colours
after CUDA's copy into GL; and in the app the owner saw H264 and VP9 move
with the right colours, through resizes, minimising and rejoining, and the
first watch after joining from the sidebar showed its picture. On AMD (RX 9070
XT desktop, Mesa 26.2.5, Nov 3) the same through VAAPI on the card that draws
the screen, not the Ryzen's iGPU beside it: `live_gpu_watch` decoded VP9 and
H264, 90 to 91 pictures in 3 s, and VP8, which AMD's VCN cannot decode, gave
up with `the GPU cannot decode this Vp8`, as the test now expects of a codec
the driver lacks; in the app the owner saw H264 and VP9 (up to 120 a second)
with the right colours, through resizes, minimising and rejoining, and a VP8
share came through the call's connection instead. Each picture leaves as an
`R8` and a `GR88` layer of one DMA-BUF in AMD's tiled layout, which EGL
imports. Every number is in `docs/gpu-codecs/STEP3_AMD.md`.

Measured against the call's path Nov 3 (RTX 3070 Ti laptop, GNOME Wayland,
the Linux debug build with the Rust library in release, Dave sharing a window
of a moving test picture, Cara watching it large with the stats card open,
`threadtop` on Cara 3 × 20 s each; `RIFT_WATCH_PATH=call` for the call's path).
The window was 1000×1080 and the share reached Cara at 46–51 pictures a
second on both paths, all that was sent:

| Cara, whole process | Through Rust (NVDEC) | Through the call |
|---|---|---|
| H264 | 28–32% of a core | 39–41% |
| VP9 | 33–35% | 52–55% |

The difference is the decoder (libwebrtc's on the CPU, 10–11% of a core for
H264 and 21% for VP9; the GPU's decoder 3–4% busy through Rust) and 3% of
the raster thread (the convert and upload). What is left is the window
redrawn at the picture's rate: the raster thread at 11–13% and the main
thread at 11–13%, the same on both paths. The watch connection's own
threads add about 4%. A 1920×1080 H264 share through Rust cost 30%, less
than the call's path at half the size.

Measured again Nov 3 in the release build, at the size the plan is about:
Dave sharing the whole 1920×1080 screen with the test picture full screen
behind Cara's window, which covered about half of it:

| Cara, whole process | Through Rust (NVDEC) | Through the call |
|---|---|---|
| H264, 54–55 a second | 33–35% of a core | 56–59% |
| VP9, 60 a second | 37–41% | 71–88% |

At this size the call's path costs far more: libwebrtc's decoder 19% of a
core for H264 and about 37% for VP9, and its raster thread 20–27% against
12–16% through Rust, where the picture is not converted or uploaded. Through
Rust the GPU's decoder was 5–8% busy and Rust's decoding thread under 2%.
What is left is the redraw, the main and raster threads at 12–17% each, in
step with the picture's rate: the release build costs no less there than the
debug one.

On AMD (Nov 3, RX 9070 XT desktop, release build, the owner watching Dave's
whole 1920×1080 screen of ffplay's test picture from the laptop, 3 × 20 s each;
`RIFT_WATCH_DECODE=cpu` keeps the watch connection on libwebrtc's decoder):

| Watcher, whole process | Through Rust (VAAPI) | Rust, CPU decode | Through the call |
|---|---|---|---|
| H264, 53 a second | 32–34% of a core | 49–51% | 54–57% |
| VP9, 60 a second | 41–42% | 48–52% | 54–58% |

There the call's own audio thread (`webrtc_audio_module`) took 14–19% of a
core on every path, watching or not, and the redraw less than on NVIDIA (main
thread 7–14%, raster 2–4% through Rust). Playing CS2 uncapped beside it,
watching through Rust added 0.10 ms to a game frame and through the call 0.16
ms, with no frame over 16.7 ms (`docs/gpu-codecs/STEP3_AMD.md`).

On Windows (Nov 4, the laptop in Hybrid: Flutter on the Iris Xe; release
build; the sharer on the same PC, its window minimised, sharing the whole
1920×1080 screen with a moving test page on half of it and the watcher's
window on the other half; 3 × 20 s each of the watcher's whole process;
`RIFT_WATCH_PATH=call` for the call's path), with libwebrtc decoding on the
CPU on both paths:

| Watcher, whole process | Through Rust (CPU decode) | Through the call |
|---|---|---|
| H264, 60 a second | 92–97% of a core | 105–108% |
| VP9 | 107–110% | 127–130% |

The difference is the convert and upload the call's path does on the CPU;
the decoder is most of what is left, and goes with phase B. The VP9 share was
encoded on the CPU by the sharer beside it, and its rate was not read.

With phase B (Nov 4, the same set-up; `RIFT_WATCH_DECODE=cpu` keeps the watch
connection on libwebrtc's decoder; the stats card read 60 a second of VP9 at
10 Mbps and 61 of H264 at 14.4):

| Watcher, whole process | Through Rust (D3D11) | Rust, CPU decode | Through the call |
|---|---|---|---|
| H264, 60 a second | 70–76% of a core | 92–97% | 97–99% |
| VP9, 60 a second | 71–76% | 110–117% | 115–118% |

Decoded on the GPU, watching costs about a quarter less than through the
call for H264 and well over a third less for VP9. Where the rest goes was not
broken down by thread. The screen behind differed from phase A's runs, so the
two tables are not one series.

Playing CS2 beside it (Nov 4, the laptop in Discrete, where Flutter, the
decoder and the game share the RTX 3070 Ti; release build; CS2 in a 1280×720
window with the watcher's window beside it, since a game covering Rift turns
the stream's pictures off; the sharer and the shared page on the same PC in
every case; H264 at 946×1032; 3 × 60 s of PresentMon per case, uncapped):

| CS2, uncapped | Mean frame | Fps | p99 | Worst |
|---|---|---|---|---|
| Not watching | 3.15–3.20 ms | 313–318 | 5.7–5.8 ms | 8.0–21.4 ms |
| Through Rust (D3D11) | 3.31–3.43 ms | 292–302 | 6.0–6.2 ms | 9.0–9.8 ms |
| Through the call | 3.57–3.66 ms | 273–280 | 6.4–6.5 ms | 8.9–10.4 ms |

Watching through Rust added about 0.22 ms to a game frame and through the
call about 0.43 ms. No frame went over 16.7 ms while watching; not watching
had one each in two rounds (21 and 20 ms). Capped at 120, every case held
118–120 fps with a p99 of 11.5–11.7 ms. The stream's own rate and its
freezes were not recorded (`docs/gpu-codecs/STEP3_WINDOWS.md`).

The same in Hybrid (Nov 4; CS2 on the RTX, Flutter and the decoder on the
Iris Xe, which also shows CS2's frames; H264, the tile reading 720p60;
otherwise as above):

| CS2, uncapped | Mean frame | Fps | p99 | Frames over 16.7 ms a minute |
|---|---|---|---|---|
| Not watching | 6.92–7.36 ms | 136–145 | 13.1–15.1 ms | 9–45 |
| Through Rust (D3D11) | 7.49–8.76 ms | 114–134 | 14.7–16.8 ms | 14–71 |
| Through the call | 8.62–9.05 ms | 111–116 | 16.9–18.6 ms | 78–141 |

Watching through Rust added about 1.2 ms to a game frame and through the
call about 1.7 ms, each against the rounds between its own. CS2 runs at half
its Discrete rate here whether watched or not, with the RTX busy only
2.3–3.0 ms a frame, so something other than the RTX's work sets its pace;
that was not broken down. The worst frames (70–107 ms) came in rounds without
watching as well as with. Capped at 120, no case held it, not watching
included (103–108 fps).

On AMD (Nov 5, the RX 9070 XT desktop under Windows 11, the only GPU there;
release build; Dave sharing from the laptop; `docs/gpu-codecs/STEP3_AMD.md`,
*On Windows*). H264 and VP9 decoded on the 9070 XT through D3D11, the runner
reading the decoder's slices directly (the card makes shader views of them),
and VP8 through the call by name. The watcher's whole process, 3 × 20 s each,
Dave's whole 1920×1080 screen of a test picture:

| Watcher, whole process | Through Rust (D3D11) | Rust, CPU decode | Through the call |
|---|---|---|---|
| H264, 60 a second, about 13 Mbps | 77–80% of a core | 93–99% | 94–109% |
| VP9, 60 a second, about 10 Mbps | 72–76% | 100–106% | 102–113% |

CS2 uncapped in a window beside the watcher's, in front, standing still,
watching a moving bar shared as H264 1080p60, 3 × 60 s of PresentMon each:

| CS2, uncapped | Mean frame | Fps | p99 | Over 16.7 ms |
|---|---|---|---|---|
| Not watching | 1.627–1.629 ms | 614–615 | 3.33–3.35 ms | 0 |
| Through Rust (D3D11) | 1.744–1.768 ms | 566–573 | 3.57–3.59 ms | 0 |
| Through the call | 1.953–1.981 ms | 505–512 | 3.74–3.77 ms | 0 |

Watching through Rust added 0.13 ms to a game frame, through the call
0.34 ms. The stream itself was measured beside the game this time, from a
strip of the watcher's tile grabbed 240 times a second for 60 s: the bar
moved 60.0 times a second on both paths, its longest hold under 30 ms, so no
freeze over 50 ms. In 600 grabs of the tile with CS2 in front, none was torn
on either path.

## How a call is played out on the desktop — [Implemented October 2026]

On the desktop, everything a call plays — voices, a share's sound, a bot —
passes through WebRTC's audio processing module on its way out, not around
it. The library flutter_webrtc ships always installs a render
pre-processor (an empty one unless set), and with one installed WebRTC plays
the module's own copy of the audio instead of the audio. That copy runs at the
module's processing rate, and that is the capture rate, 16 kHz until the
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

**What it sends is silence.** The receiving end plays what it gets like any
call audio, so until Nov 5 2026 the warm-up played your own microphone back to
you for its half second, about 450 ms of it as loud as it was recorded. The
track now goes off before it is added. It still records, which is all the
module needs, and sends silence. Measured Nov 5 with a probe on the app's own
WebRTC build and a test microphone playing a tone: a 12 kHz test sound in the
call after the warm-up came through at the same level with the track off as
with it on, and was gone without the warm-up. What remains is libwebrtc's, not
the warm-up's: each time recording started (a second warm-up in the same run
too), about 40 ms of the microphone, some 15–20 dB down, reached the output,
with either end of the connection or both turned off. Whether a first unmute
in a call does the same was not measured.

**On Windows, libwebrtc is kept off the system's echo canceller.** With echo
cancellation on, its audio device asks for the Voice Capture DMO
(`CLSID_CWMAudioAEC`) when it is created, and when one is there it records
through it and turns its own canceller off. The DMO records 16 kHz mono, so the
module and its copy ran at 16 kHz once the microphone had started: a call heard
on Windows was cut just under 8 kHz, and every Windows microphone was sent that
way. It is also what the VM measured in October, 14 kHz until recording and
7.4 kHz with the warm-up. libwebrtc has no switch for it, so the runner registers
the DMO's class in its own process with a factory that refuses
(`windows/runner/echo_canceller.h`), and libwebrtc cancels echo itself at 48 kHz,
as on Linux. If registering fails, the DMO is used as before.

Without the DMO Windows has Linux's 16 kHz start, so the warm-up runs there too.
It adds no ducking: the old build already took another app's 17 kHz tone down
18 dB on joining muted, with nothing recording, and the warm-up build did the
same at the same moment. Windows' microphone icon should show for the half
second, as it did in October (not looked at this time). A PC with no microphone
has nothing to warm up with, so it should stay
at 16 kHz where the DMO's build played 14 kHz (not measured).

Measured Nov 5 2026 in the Windows 11 VM against 1.5.2-beta.10, the VM's output
into VB-Cable and the cable as its mic, so the mic hears everything the call
plays. Far end on Linux, noise filters off.

| | System canceller | Rift's own |
|---|---|---|
| Highs heard, echo cancellation on | 7.5 kHz | 15.0 kHz |
| Highs heard, joined muted | 14–15 kHz | 14–15 kHz (8 kHz without the warm-up) |
| Mic sent, 8–10 kHz | −56 dB | −16 dB |
| Echo sent, a voice call at −31 dBFS | −43 dBFS | −87 dBFS |
| Echo sent, a song shared at −30 dBFS | −47, −48, −76, −80, −85 dBFS | −69, −72, −73 dBFS (−60 just after an unmute) |
| Voice alone, gain | −10.7 dB | −9.8 dB |
| Voice over the far end, gain | −20 to −23 dB | −12 to −19 dB |

Rift's own is worse in three ways. **The far end's first unmute** after you join
takes your voice down harder: over a few seconds of speech, about 30 dB down for
a second or so in two runs of three, where the DMO's dip was 15–20 dB (the
"Linux" line in `TESTING.md`, *Elsewhere*). **Turning echo cancellation on
mid-call** takes it a while to settle, −52 to −81 dBFS at first. **A test sound
that jumps between the ears** leaked, mostly −20 to −30 dBFS with some seconds
near −90; the DMO also leaked it, −21 in one run and bursts of −38 to −65 in the
next, and the song above did not.

Neither canceller takes out sound played outside libwebrtc. A clip from another
app reached the far end at the same level on both. The Rust path's player is such
a stream, so its sound is not cancelled on Windows or Linux: on a real Windows
laptop on speakers (Nov 5), the other side heard the watched share come back
through the mic, by ear, not measured.

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

**Held from the moment it arrives.** A remote track plays as soon as WebRTC
has it, and the app hears of it later: on a join it waits until the room is
connected. So joining a call with a share in it played up to 80 ms of the
share's sound, just before the join chime (reported Nov 5 2026 on Windows and
Linux). Now every remote audio track is turned off the moment Dart hears of it
and turned on when it starts, unless the app says it is held
(`Room.audioHeldOnArrival`, asked with `hearsRemoteAudio`'s answer;
`third_party/livekit_client/RIFT_PATCHES.md`, patches 9 and 10). Measured Nov 5
in the real app on the local stack, Linux, a 5 kHz tone as the share's sound:
the tone in 8 joins of 13 before, starting up to 56 ms before the hold, and in
none of 13 after. Starting a track first, patch 9 alone, had passed a probe
with no call encryption and did not stop it in the app.

The web needed one more step. Chrome can play a disabled track attached to an
`<audio>` element when sound starts, so a held track's element is muted until
the track is first turned on (patch 11). Measured Nov 5 in headless Chrome: 5 of
11 rapid rejoins began with 120–200 ms of the share's sound at full level, though
the held track was never turned on; none of 14 after.

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
runs the noise model on it, so DPDFNet takes its 2 to 8 ms of every 10 ahead of
a game. That is a price chosen on purpose. From Oct 25 to Oct 31 2026 the model
had a thread of its own at normal priority, sharing the cores with the game,
where a frame it was late with went out unfiltered. On that build (beta.9)
testers heard a Windows friend's voice crackle and cut out, so beta.10 let them
switch between the mic's thread and the model's own at each priority in a call.
The owner compared them by ear on Oct 30: the mic's thread sounded best, so
that is where the model runs, on Linux too, where the thread is at normal and
what goes is the wait for another thread. The same comparison had a setting to
hold Windows' 1 ms timer and stay unthrottled for the length of a call. It was
left out: its main reason was the mic's wait for the model's thread, which is
gone, and Rift already asks for that timer in a call without it (`powercfg
/energy` in the Windows 11 VM, Oct 30). A share holds both itself
(`rust/src/screenshare/capture.rs`). Not measured: Rift unthrottled or not
while a game covers it in a call.

What the placement costs a game, measured Oct 25 2026 on a laptop's Windows,
the model on the mic's thread: with a stand-in game on every CPU, the game's
frames taking over 1.5 times its fastest went from 0.16–0.31% with the filter off to 0.83–0.92% on DPDFNet-2, and its
99.9th percentile from 8.2 to 12.2 ms. With the model on its own thread at
normal (measured the same day, the same laptop), CS2 limited mostly by the CPU ran
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
