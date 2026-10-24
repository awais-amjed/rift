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
from the same library as Linux's VAAPI below, tried in that order. **Media
Foundation** is the fallback on AMD's GPUs only, where the library will not
load or AMF will not open; where neither opens, the share goes out as VP9.
Media Foundation is not the fallback for NVIDIA's and Intel's GPUs: NVIDIA's
encoder there crashed a 120 fps share twice in two runs.
Media Foundation reaches all three makers' encoders but runs past WebRTC's
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
- **GPU H264 stays constrained baseline**: LiveKit offers only that profile for
  pre-encoded tracks, and Firefox viewers cannot take High.
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
  Windows Intel's runtime writes the header itself, as type 7, for Quick Sync
  and Media Foundation alike, with no setting to change it, on Linux so
  does Mesa's encoder for AMD whatever FFmpeg hands it, and on Windows so do
  AMD's AMF and its Media Foundation encoder. So a share
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
choice from the registry (`UserDuckingPreference`). `DuckingCubit` counts the
ducks while the choice lowers others, and `DuckingHintListener` shows a toast
during a Rift call: it explains what happened, offers "Fix it" (Settings →
Voice & audio, scrolled to the section and lit up) and "Don't show again"
(`AppState.showDuckingHint`). The section shows the choice live, re-read when
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
