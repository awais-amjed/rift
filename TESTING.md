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
| An expired invite is refused | Oct 1 2026 | Windows 11: a 1-hour invite whose `expires_at` was moved to 20 s ahead in the database (rather than waiting the hour), then pasted on a fresh profile after it passed: the Join dialog says "Invite code has expired" and the invite keeps 0 uses |
| A music bot playing into a call (SDK `example/music_bot.ts`) | Oct 1 2026 | Windows 11, two clients muted in a call, the bot fed a 660 Hz test tone over HTTP through ffmpeg: `/play` brings it in and both clients play the tone (each app's own audio session measured, plus the speakers' loopback); the panel's Stop and `/stop` silence it and keep the bot in the call; `/disconnect` takes it out. In a private voice channel the summon brings it in and both hear it. **Not working:** `/disconnect` in a private channel is never handled by the bot, which then can't play there again until restarted (the SDK can't report a dropped room); and a member who didn't send the command keeps a stale "summoned" row. |
| Rift DMs when central can't be reached at launch | Oct 1 2026 | Windows 11, local central with its gateway stopped: "Can't reach your Rift account … Rift keeps trying" with Try again (pressing it while down keeps the state); after ~45 s down the gateway was started and the conversation list and friends were there by the first check 5 s later, with no restart (it used to say "Finding your account…" until the app was restarted). Saved central DMs are still not readable while central is down: the list itself comes from central |
| Uninstalling removes Rift's registry keys (Windows) | Oct 1 2026 | Windows 11: installer built with `scripts/build_windows_installer.ps1`, installed and uninstalled silently (the user approved both UAC prompts). The installed app, run once, wrote its notification activator key pointing at `C:\Program Files\Rift\rift.exe`; after uninstalling, no `CLSID\{919df387-…}`, `AppUserModelId\CodingFries.Rift*` or `PushNotifications\Backup\CodingFries.Rift*` key was left, including the debug profiles' (their builds rewrite them at the next start). Not driven: uninstalling from Settings → Apps, or as a user elevating with another account's credentials Again from Settings → Apps → Installed apps on Oct 1 2026: Rift listed with its name, publisher and icon; afterwards no files, uninstall entry, shortcuts or Rift registry keys remained. |
| Pressing a message notification (Windows) | Oct 1 2026 | Windows 11, debug build, profiles wa and wb on one PC. A on another server, minimised; B @mentioned A in #general; pressing A's toast brought A forward on that server with #general open. Then with A quit: pressing the toast started `rift.exe --rift-profile=wa -Embedding` (Windows, through the registered activator), which opened as A, waited for the vault and opened #general at the mention. A probe toast for A, pressed while B also ran, went to A, not B. Before: no press reached the app. Later the same day: a server DM toast (it shows the message text) and the same toast's entry in the notification centre after its banner was closed each brought A forward from minimised with the DM open. A DM call's toast, pressed while ringing, brought A forward with the ringing card, and Answer connected. Not driven: a Rift (central) DM toast press, the installed build, and Linux/macOS |
| Secure storage in Local AppData, per profile (Windows) | Oct 1 2026 | Windows 11, debug build, profiles wa and wb: on first launch each moved only its own keys from the old Roaming `flutter_secure_storage.dat` into `rift_<profile>\secure_storage.dat` under Local AppData and opened its vault with both servers; the Roaming file kept the other profiles' keys untouched; A restarted and opened its vault from the new file alone. Key names checked with a DPAPI script that prints names only. The release default (no profile) and the file being deleted once empty were not driven live; both are unit-tested |
| Profiles side by side keep their own central sign-in (`RIFT_PROFILE`) | Oct 1 2026 | Windows 11, two profiles on a local central: the existing session moved from the shared preferences file into the profile's own `central_auth.json` on launch (B stayed signed in); A signed in while B ran, then A was restarted and stayed signed in — before, B's next write had erased A's session twice in one evening. Linux not driven |
| Settings mic test outside a call | Oct 1 2026 | Windows 11, no call: Test mic opened the chosen input (Windows' audio sessions showed Rift recording from it) and the meter followed a phrase played into a virtual cable (10 of 24 bars) and the laptop mic hearing the speakers (4 bars); switching the input while testing moved the test to the new device; Stop released the mic. It used to stay dark with no microphone opened. In a call the test still reads the call's own levels. Linux and macOS keep the WebRTC path (untested outside a call) |
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

- **macOS.** Configured (entitlements, usage strings, notifications) but never
  launched.
- **Windows, the parts not reached** (driven Sep 29 – Oct 1 2026 on Windows 11 with
  debug clients side by side and the installer): a second monitor with a different
  scale, and losing a server that
  runs on another machine (the server was on the same PC, so the Wi-Fi test never
  cut Rift off from it).
- **iOS, and push on it (APNs).**
- **Push for DM calls** — the phone's Answer/Decline notification and a woken phone
  ringing. The relay is central's, so this waits for central on its server.
- **A real certificate on a self-hosted server.** Every pass has reached the gateway
  over http, so Caddy has never completed an ACME challenge — and Android refuses
  cleartext, which makes this the one gap between self-hosting and a phone.
- **Key rotation in a text channel** while someone is reading it, and scrollback
  across two key versions. (A voice key rotating mid-call is covered.)
- **`rift://` invite links**, since they were last changed. On Windows nothing
  registers the scheme at all (checked Oct 1 2026), so a link there opens nothing.
- **The region probe choosing between genuinely distant nodes** — both test nodes
  were on one machine.
- **The `studio` profile** of the self-hosted stack.
- **Saved conversations: central DMs while central is down.** Channels and server
  DMs were driven (Sep 28, and on Windows Oct 1), and so were the wipes on Windows
  on Oct 1: leaving a server, signing out of central, a vault reset and pruning a
  deleted channel each removed their files. A saved central DM still can't be
  opened while central is unreachable, because the list itself comes from central.

## Known small issues

Found while driving the app and left open, because none of them stops a feature
from working. Most were found on Windows (Sep 29 – Oct 1 2026) but are not
Windows-specific. Remove a line in the commit that fixes it.

**Messaging and DMs**
- Accepting a DM request doesn't tell the sender: they stay on "Your message
  request is waiting…" with the composer locked until they reopen the
  conversation. `answer_dm_request` only announces to the accepter's own devices.
- A refused DM (blocked, or over the new-DM limit) clears the composer, so the
  text is lost.
- The Server DMs unread badge counts a message that was deleted before it was read.
- Offline, mentions show the username (`@tester_a`) instead of the display name
  until the members load.
- Quitting the app never counts as leaving the open conversation, so its saved copy
  misses your last sends until the next online open. A server DM also stays open in
  `DmCubit` when you click away to a channel; narrowing the window below 700 then
  puts that DM back over the channel you were reading.
- A used-up invite is refused as "Invalid invite code", without saying it was used.
- A changed safety key is flagged only inside the person's profile; the DM
  header's "Encrypted" chip stays green.
- Signing a device back in to the account whose cloud backup *is* this vault still
  asks "Two identities — Keep cloud / Keep this device", and the vault password was
  asked again on the next restore although the first said future restores would be
  automatic.

**Servers and moderation**
- No kick: the "Kick members" permission is granted to Moderators but does nothing.
- An open profile doesn't refresh live ("Timed out until…" stays after it ends), and
  Manage server → Members' count lags right after a ban is lifted.
- Choosing "Only @mentions" for a channel while its server is on the default stores
  nothing (it equals the default), so switching the server to All later carries
  the channel along. By design per `_setLevel`; still surprising.

**Sidebar and layout**
- Clicking the still-highlighted channel while Server DMs is showing closes it
  ("No channel selected"); a second click opens it. The sidebar highlights both.
- The members count is one higher in the compact sheet than in the desktop header
  (one counts the bot).
- Between 700 and 1099 wide, Escape doesn't close the members overlay (a click
  outside does).
- The welcome card at the default 1280×720 window runs past the bottom edge.

**Voice and calls**
- Rift's own sounds (the ring) play on the system default output, not the output
  chosen in Settings.
- The soundboard volume slider is disabled while "Mute everyone else" is on, yet
  your own clips still play at that volume.
- A caller who hangs up while it rings is told "… didn't answer", like a timeout.
- A deafened member shows deafen + mute in the sidebar but only mute on their tile.
- The Share sound picker lists other Rift windows on the same PC (only possible
  with several instances; sharing one would loop the call into itself).
- A shared window that is minimised freezes on its last frame for viewers, with no
  hint that it's paused (Windows sends no frames for a minimised window).
- Once, the speaking glow didn't light for about ten minutes although audio
  flowed. Not reproduced.
- A summoned bot that someone else sends away stays drawn as "summoned" for members
  who didn't send the command: only the sender re-reads the summons
  (`VoiceListenersCubit.refresh`).

**Bots**
- A bot's changed command list reaches an open channel only when it is reopened;
  until then a new command goes out as ordinary encrypted text the bot can't read.
- With the command suggestion showing, Enter accepts it and a second Enter sends.
- SDK, `example/music_bot.ts`: in a **private** voice channel `/disconnect` is
  never handled. The client drops the summon first, and the bot can't find the
  channel through `voice_roster`. The server still removes it from the room, but
  the panel keeps saying "Now playing" and every later `/play` there fails until
  the bot restarts, because `VoiceConnection` can't report a dropped room.

**Keyboard and accessibility**
- Create channel dialog: Tab never reaches the Private channel switch, and the
  focused Cancel button shows no focus ring.
- Windows: after closing a native Save dialog with a key, the first Escape is
  ignored (closing it with the mouse is fine). Looks like the Flutter embedder.
- Windows: only the topmost pixel of the window resizes from the top edge (about
  8 px on the other edges).

**Windows only**
- Once, a client stopped drawing with its render thread spinning inside the Intel
  Iris Xe driver (31.0.101.4502). Not reproduced; if it repeats, try turning
  Impeller off in the runner, and a newer driver.
- Uninstalling cleans the notification registry keys of the account that approved
  the UAC prompt, so another admin's password leaves the user's own keys behind.

**Elsewhere**
- Linux: the audio device pickers still say "No devices found" outside a call, and
  "System default" is saved but not applied. The plan is in `LINUX_AUDIO_DEVICES.md`.
- rift-central: `stack/setup.py` writes `kong.yml` with mode 0600, which the Kong
  container (uid 1001) can't read on a Docker that enforces bind-mount permissions,
  so `up.sh` stops at "dependency kong failed to start".

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
