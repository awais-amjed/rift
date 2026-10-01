# Testing

Three layers, and each one sees something the others cannot:

| Layer | Covers | Run |
|---|---|---|
| `flutter test` | pure logic, crypto, models, and widget layout invariants | `flutter test` here |
| The schema suites | row-level security, grants, triggers — what each role can actually reach | `./scripts/db_test.sh` in `rift-self-host` and in `rift-central` |
| Driving the real app | realtime delivery, key distribution, presence, LiveKit, push, layout at a width | by hand, below |

The third layer is recorded here as a **status table**: what has been driven through
the real UI, when, and what has not. The full dated log each row comes from is a
working diary kept locally (`MANUAL_TESTING.md`, gitignored). When you verify
something live, add it to the log and update the row here in the same commit as the
change — a row that overstates what was checked is worse than no row.

---

## Status

Last verified live, newest work first. "Two clients" means two Linux desktop
instances with separate identities; the Android client is the emulator.

| Area | Last verified | How |
|---|---|---|
| Choosing the input and output device outside a call | Oct 1 2026 | Windows 11: Settings → Voice & audio with no call up now lists Windows' devices (it used to say "No devices found"); the laptop mic and a virtual cable picked there were what the client recorded from and played to on joining (read from Windows' audio sessions), and "System default" picked there moved both back to Windows' defaults on the next join. Picks in a call still apply at once. Linux and macOS still list nothing outside a call |
| A Windows mic staying alive after the last other voice leaves (and after deafening) | Oct 1 2026 | Windows 11, two clients, the other side's voice measured on the speakers. Before: A unmuted, B (with a published mic) leaves for 15 s and rejoins — A sent digital silence until A rejoined ("capturing thread has ended prematurely" in A's WebRTC log). After: the same, plus A muted while B leaves (unmutes alone, or after B is back) and A deafening for 10 s — A heard every time (-17 to -31 dBFS), the mic republished once each time, no capture death logged. Output switching mid-call while unmuted also kept A's mic. Linux and macOS do not use this path |
| Picking the input and output device in a call, and going back to "System default" | Oct 1 2026 | Windows 11, two clients; which device each process actually had open read from Windows' audio sessions. Input (first-listed input a virtual cable, Windows' default the laptop mic): picking the laptop mic mid-call, then a mute and unmute, a leave and rejoin, a switch while muted, "System default" from the cable, and a fresh launch on "System default" all kept or moved capture to the right device (each used to end up on the first-listed input). Output: "System default" from a virtual cable moved playout back to the speakers mid-call, and the other client's voice measured there at -17 dBFS (it used to stay on the cable until a restart). Linux and macOS not driven |
| "Can't reach <server>" chip in the desktop title bar (the selected server's socket down; "No internet" takes its place when offline) | Oct 1 2026 | Windows 11, `docker stop rift-kong` with a client on the server: the red chip appeared 5 s after the stop (the settle) and was gone 3 s after Kong started again, when the socket reopened (title bar recorded every second). Precedence and switching servers covered by widget and cubit tests only; Linux, macOS and phone layouts not driven |
| "No internet" chip in the desktop title bar | Oct 1 2026 | Windows 11, real Wi-Fi off for ~16 s: the chip appeared 2 s after the drop (the settle), stayed while off and was gone within a second of Wi-Fi coming back (title bar recorded every 2 s); WSL's virtual switch and Tailscale, still up, did not count as online. Linux, macOS and phone layouts (no title bar) not driven |
| Reopening the desktop window on a screen that exists (size and place fitted to the work area) | Oct 1 2026 | Windows 11, one 1920×1080 display: a client saved at 1280×720 logical at 100 % reopened at 150 % fitted to the work area instead of past the edges and under the taskbar; at 100 % three clients reopened where they were. Unplugged or mixed-scale second monitors not tried (no second monitor) |
| Conversations saved on the device: drawn on open, offline, replaced by the fresh page | Oct 1 2026 | Windows, two clients, gateway stopped: channels and server DMs, a row deleted while closed, own messages; the server DM list now loads by itself when the server comes back after an offline start (it used to stay empty). Wipes on leaving a server and on a vault reset, files unreadable, pruning a deleted channel. Central DMs and the sign-out wipe not driven |
| One-to-one calls in server DMs | Sep 27 2026 | two clients + Android; ringing, answer from anywhere, decline, missed, audio both ways recorded, tracks encrypted |
| Server moderation: reports, time-outs, bans, DM requests, blocks | Sep 27 2026 | two clients + headless members; security pass probed the database and realtime directly |
| Wording and UI for moderation and DM calls | Sep 27 2026 | two clients; the time-out menu and banner, including expiry |
| Directory moderation (`rift-admin`) | Sep 26 2026 | local central; second factor enforced, lockout after five wrong codes |
| Central's own stack, backups and restore | Sep 26 2026 | local stack; encrypted backups to a stand-in S3 bucket, then a wiped stack restored with every account, vault and attachment intact |
| Web build | Sep 26 2026 | Chrome, before deploying |
| Pins and polls | Sep 26 2026 | two clients |
| Voice regions: pinning, moving a live call, a region dying | Sep 25–26 2026 | two clients on two LiveKits on one machine |
| Roles, bans, bots in a call | Sep 23 2026 | a clean stack driven end to end |
| Safety codes | Sep 22–23 2026 | two clients, both ends |
| Screen share, including a phone's stream | Sep 22 2026 | Linux sharing, desktop and Android watching |
| Push-to-talk on Linux | Sep 21 2026 | GNOME, through the GlobalShortcuts portal |
| Server rail order across devices | Sep 21 2026 | one account on two devices, and a reorder made offline |
| Soundboard | Sep 20–21 2026 | two clients in a call |
| Replies, forwarding, jumping to a message | Sep 20 2026 | two clients, channel to channel |
| People profiles | Sep 20 2026 | both tiers |
| Bot directory | Sep 20 2026 | publish, browse, like, add |
| Operator limits | Sep 19 2026 | two clients; each cap refuses and says why |
| A server built from nothing, with a bot | Sep 6 2026 | the console's stack, two clients, a bot through the SDK |
| Encrypted voice, audio both directions | Sep 2 2026; Sep 30 2026 | two clients on virtual microphones, a key rotation mid-call; on Sep 30 (Windows) one minted by a client in the call, which has to move its own call too |
| Friends gate on central | Aug 25 2026 | browser |
| Notification levels, desktop notifications, FCM push | Aug 24–25 2026 | two Linux clients; Android through the relay |
| Messaging, attachments, voice notes, server DMs, kick and ban | Aug 23 2026 | Linux, Android and web |

## Not verified yet

Don't read the table as "everything works". Still owed:

- **Windows and macOS.** Nothing has been driven on either. macOS is configured
  (entitlements, usage strings, notifications) but has never been launched.
- **iOS, and push on it (APNs).**
- **Push for DM calls** — the phone's Answer/Decline notification and a woken phone
  ringing. The relay is central's, so this waits for central on its server.
- **A real certificate on a self-hosted server.** Every pass has reached the gateway
  over http, so Caddy has never completed an ACME challenge — and Android refuses
  cleartext, which makes this the one gap between self-hosting and a phone.
- **Key rotation in a text channel** while someone is reading it, and scrollback
  across two key versions. (A voice key rotating mid-call is covered.)
- **`rift://` invite links**, since they were last changed.
- **The region probe choosing between genuinely distant nodes** — both test nodes
  were on one machine.
- **The `studio` profile** of the self-hosted stack.
- **Saved conversations: central DMs, and the wipes.** Channels and server DMs
  were driven (Sep 28). Leaving a server, signing out of central and a vault
  reset removing their files are covered by `test/message_cache_test.dart`
  only, and so is pruning a channel the server stops listing.

---

## How to drive the app

### Linux desktop

Run two instances with separate profiles, so they have separate identities:

```sh
RIFT_PROFILE=t1 GDK_BACKEND=x11 flutter run -d linux
RIFT_PROFILE=t2 GDK_BACKEND=x11 ./build/linux/x64/debug/bundle/rift   # after the first build
```

Launch the second from the built bundle: two `flutter run`s contend on
`.dart_tool/flutter_build`. A profile's files are in
`~/.local/share/com.codingfries.rift/rift_<profile>`, but its identity lives in the
system keyring, so copying a profile directory gives a client that cannot sign in; to put one identity on
two clients, use **Export to File / Restore from File** in Cloud Backup.

**Input goes through `scripts/uinput_drive.py`, not `xdotool`.** GNOME on Wayland
refuses XTEST without saying so: `xdotool mousemove` returns success and nothing
moves, which looks exactly like the app ignoring clicks. A uinput device is a real
input device to the compositor. It needs the `input` group, no root.

```sh
python3 scripts/uinput_drive.py serve &          # hold one device open for the session
python3 scripts/uinput_drive.py send move 162 273
python3 scripts/uinput_drive.py send click 162 273
python3 scripts/uinput_drive.py send type 'hello'
python3 scripts/uinput_drive.py send key ctrl+l
xdotool search --name '^rift$'                   # window ids — window management still works
xdotool getwindowgeometry --shell <id>           # its origin, for screen coordinates
import -window <id> shot.png                     # screenshot of one window
```

What costs time if you don't know it:

- **Screen coordinates = the window's origin + the offset in its screenshot.** Read the
  origin right before each click: the compositor can move a window back after
  `windowmove`.
- **`xdotool windowactivate <id>` before every pointer move.** With nothing focused the
  compositor drops the events. Then **`move` before `click`**: the first click after
  activation is often eaten by focus. Never blind-double-click — a second click can land
  on whatever the first one opened.
- **Screenshot after every click.** Layout shifts, and a stray dialog can eat clicks while
  `import -window` still shows the window's own buffer.
- **Kill by PID.** `pkill -f` with a pattern that appears in your own command line kills
  your own shell.
- **Check the pointer actually moves** before concluding anything about the app — without
  the desktop's screen-control permission every event is silently dropped.
- `move` cannot follow a submenu: it resets against a screen corner first, which closes
  hover menus. Nudge from where the pointer already is.

Audio can be tested for real by giving each client its own PulseAudio null sink as
microphone and speaker, and recording the other side, so a call's sound is measured
rather than judged by ear.

### Android (emulator)

```sh
flutter run -d emulator-5554
adb -s emulator-5554 exec-out screencap -p > shot.png
adb -s emulator-5554 shell input tap <x> <y>                  # device pixels
adb -s emulator-5554 shell "input text 'a%sb'"                # %s is a space
adb -s emulator-5554 shell input swipe <x> <y> <x> <y> 900    # long-press
```

- The emulator reaches the host's stack on the machine's **LAN address**, not
  `localhost` — and so must the LiveKit URL.
- Don't send `KEYCODE_BACK` from the root screen: it leaves Rift and the setup wizard
  takes over. Relaunch with `am start -n com.codingfries.rift/.MainActivity`.

### Web (Chrome)

Chrome runs as a native Wayland client that `xdotool` cannot see, so drive it over the
DevTools protocol with `scripts/cdp.py` instead. Screenshots come back as the viewport,
so coordinates need no window arithmetic.

```sh
flutter run -d chrome
port=$(ps -eo args --no-headers | grep -o '\-\-remote-debugging-port=[0-9]*' | head -1 | cut -d= -f2)
python3 scripts/cdp.py $port shot page.png
python3 scripts/cdp.py $port click 700 669
python3 scripts/cdp.py $port type 'hello'
python3 scripts/cdp.py $port setfile <path>    # the only way to hand the page a file
```

- Pin the viewport with `Emulation.setDeviceMetricsOverride` so coordinates are stable,
  and to test breakpoints without resizing a window.
- A backgrounded tab stops rendering and screenshots time out — bring it forward first.
- `flutter build web` while `flutter run -d chrome` is live fails with a bare "Failed to
  compile": both write `.dart_tool/flutter_build`.

### macOS

Prepared without a Mac, so the first `flutter run -d macos` is itself the test. Build the
Rust crate on its own first (`cd rust && cargo build`) to see its errors separately. If a
call has no audio, check the microphone entitlement before anything else — a missing one
fails silently.
