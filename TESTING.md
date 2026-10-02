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
| A deafened person's tile | Oct 2 2026 | Linux, Lana and Benny in #voice: Benny deafened, and Lana saw headphones and a crossed mic on his tile, as in the sidebar (the tile used to show only the mic); undeafening took the headphones away. Moderator deafen not driven (same roster flag, unit-tested) |
| A deleted message comes off the unread badge | Oct 2 2026 | Linux, Lana in #general: Benny DMed her and Server DMs showed 1; he deleted it and the badge cleared within 3 s. The same for a message in #lounge and its channel badge. An edit with something unread (which also counts again) not driven |
| No Rift in the Share sound list | Oct 2 2026 | Linux, Lana and Benny in a call: with Lana's call stream playing (PulseAudio binary `rift`), Benny's Share sound said "Nothing is playing"; with `paplay` also playing, it listed only paplay. Windows not driven (same filter, unit-tested on its `rift.exe` names) |
| Mention names in a saved copy | Oct 2 2026 | Linux: Benny wrote "@Lana" in #general; Lana left the channel (which saves it), quit, and relaunched with `rift-kong` paused. #general drew from the copy with "@Lana", not "@lana_clean" |
| Channel order and a used-up invite on joining | Oct 2 2026 | Linux, a fresh privacy-mode profile joined Rift Test with a one-use invite: the sidebar listed general, lounge, random and lounge-voice, voice, by name like everyone else's (the join used to give creation order). The same invite again said "That invite doesn't work. It may be used up, expired or withdrawn, or mistyped." The member was deleted afterwards |
| The welcome card at the default window size | Oct 2 2026 | Linux, a fresh profile at the default 1280×720: the whole card and the step dots fit, with about 40 px to spare under the dots. Before, the card's lower edge and the dots were cut off. Not checked on Windows, whose text was slightly taller in the earlier pass |
| Enter on a whole bot command sends it | Oct 2 2026 | Linux, #general on Rift Test with a bot whose commands are `/play <url>`, `/stop` and `/disconnect`: `/stop` typed in full went out on one Enter (it used to need two); `/st` and `/play` completed to `/stop ` and `/play ` and sent nothing. Tab completing without sending is covered by `test/composer_command_enter_test.dart` only. The bot was not running, so nothing answered the `/stop` |
| The soundboard volume while everyone else is muted | Oct 2 2026 | Linux, Settings → Voice & audio and the soundboard panel in a call: with "Mute everyone else" on, the slider stays usable, shows the real volume (60%, then 30% after a drag) and says only your own clips play now. It used to grey out and read "—". Whether your own clip then plays at that volume was not measured; that rule is unchanged and unit-tested (`SoundboardVolume`) |
| Sending is held to a verified person whose key changed | Oct 2 2026 | Linux, Lana and Benny's server DM: Benny marked verified ("They match"), his `chat_public_key` swapped for Tom's in rift-db, Lana relaunched: amber chip, a new key-change line, and the composer replaced by "Benny's safety key changed since you verified them…" with Compare codes; Forward from #general listed echo and not Benny. Closing the code sheet with X kept it held; "Forget" brought the composer back and the chip went green. Not driven: central DMs (same gate, `central:` record), "They match" on the new code |
| Keyboard through Create channel | Oct 2 2026 | Linux: Tab goes name → Text → Voice → Private channel switch (white ring) → Space turns it on → search → each member row (tinted in turn) → Cancel → Create channel (both ringed). Before, Tab skipped the switch, the buttons showed nothing and the rows' tint was painted under the list's fill. Not driven: the other dialogs' switches and buttons (same widgets), light theme |
| Escape closes the members overlay | Oct 2 2026 | Linux at 940 px: with the composer focused, Escape closed the overlay; with a member's context menu open over it, the first Escape closed the menu and the second the overlay. Not driven: Android back (unchanged, `PopScope`) |
| The members count is the same at every width | Oct 2 2026 | Linux, Rift Test (4 people and a bot): the overlay header at 940 px, the compact sheet and the channel header's "4 members" at 480 px all say 4; the bot is counted under its own Bots heading |
| A caller hanging up mid-ring | Oct 2 2026 | Linux, Lana calling Benny in their server DM: hung up at 21 s (stored `missed`), Lana's line reads "You cancelled a call" and Benny's "Missed call from Lana"; left to ring out (30.1 s), "Benny didn't answer". Not driven: a hang-up under 15 s (unchanged, `cancelled`) |
| Realtime after the gateway drops, and after launching on an expired token | Sep 30 – Oct 2 2026 | Windows (Sep 30): a realtime restart and a 60 s gateway stop recovered, and launches on overnight-expired tokens joined everything. Linux (Oct 2): launches on days-old tokens joined everything; one 60 s gateway stop in nine left `server:`, `user:` and the open `chat:` stuck joining and off the socket for good, on both clients. Cause found in realtime_client and patched (`third_party/realtime_client`). Checked the same day with topic state read from the running app, the server's topic check slowed on purpose (`pg_sleep(0.2)` in `app.can_use_topic`, about 2 s per join) so the reconnect race happens every time: the 2.13.0 build lost all four topics after a 30 s gateway stop and still had only `presence:` and `voice:` four minutes later; the patched build kept all four on the socket and had them joined within two minutes, and joined at once after an ordinary-speed stop. Two clients on the patched build, also Oct 2 (Lana and Benny, both with #general open): four gateway stops of 30, 60 and 90 s, and after each one a message each way in #general and an unread badge in a channel the other didn't have open, all four arriving within seconds. With the topic check slowed to 2 s a call (the same ~2 s per join as above, now that a join asks once — see `rift_topic_read` in rift-self-host), messages sent two minutes after a 30 s stop all arrived, but late, the last up to ~45 s after it was stored; when each topic joined was not measured |
| Leaving a server and coming back with a new invite | Sep 30, Oct 2 2026 | Windows (Sep 30) and Linux (Oct 2): the member came back as themselves with their messages, whatever names were typed, and the invite was not used up; on Windows a banned member was told so |
| An expired invite is refused | Oct 1 2026 | Windows 11: a 1-hour invite whose `expires_at` was moved to 20 s ahead in the database (rather than waiting the hour), then pasted on a fresh profile after it passed: the Join dialog says "Invite code has expired" and the invite keeps 0 uses |
| A music bot playing into a call (SDK `example/music_bot.ts`) | Oct 1 2026 | Windows 11, two clients muted in a call, the bot fed a 660 Hz test tone over HTTP through ffmpeg: `/play` brings it in and both clients play the tone (each app's own audio session measured, plus the speakers' loopback); the panel's Stop and `/stop` silence it and keep the bot in the call; `/disconnect` takes it out. In a private voice channel the summon brings it in and both hear it. A `/disconnect` in a private channel used to leave the bot holding a dead connection, unable to play there again until restarted; since Oct 2 the SDK reports a dropped room (`VoiceConnection.closed`): on Linux, Oct 2, with the bot playing, its summon was deleted and it was removed from the room through LiveKit's `RemoveParticipant` (what the server does) without the bot seeing a command — the panel turned to "Stopped", ffmpeg exited, and the next `/play` joined again and played. Done in a public channel standing in for the private case, not with a real private `/disconnect`. Also (fixed Oct 2) a member who didn't send the command kept a stale "summoned" row. Since then a summon or listening grant rings `voice_bots` on the server topic: on Linux, Oct 2, a summon row added and then removed in the database appeared and disappeared under the voice channel on both clients within 3 s, with nobody clicking (driven from the database, not through a real `/disconnect`). |
| Rift DMs when central can't be reached at launch | Oct 1–2 2026 | Windows 11, local central with its gateway stopped: "Can't reach your Rift account … Rift keeps trying" with Try again (pressing it while down keeps the state); after ~45 s down the gateway was started and the conversation list and friends were there by the first check 5 s later, with no restart (it used to say "Finding your account…" until the app was restarted). Saved central DMs are still not readable while central is down: the list itself comes from central. Linux, Oct 2: the same, local central's gateway stopped and started with nothing clicked; DMs back within 40 s |
| Uninstalling removes Rift's registry keys (Windows) | Oct 1 2026 | Windows 11: installer built with `scripts/build_windows_installer.ps1`, installed and uninstalled silently (the user approved both UAC prompts). The installed app, run once, wrote its notification activator key pointing at `C:\Program Files\Rift\rift.exe`; after uninstalling, no `CLSID\{919df387-…}`, `AppUserModelId\CodingFries.Rift*` or `PushNotifications\Backup\CodingFries.Rift*` key was left, including the debug profiles' (their builds rewrite them at the next start). Not driven: uninstalling from Settings → Apps, or as a user elevating with another account's credentials Again from Settings → Apps → Installed apps on Oct 1 2026: Rift listed with its name, publisher and icon; afterwards no files, uninstall entry, shortcuts or Rift registry keys remained. |
| Pressing a message notification (Windows) | Oct 1 2026 | Windows 11, debug build, profiles wa and wb on one PC. A on another server, minimised; B @mentioned A in #general; pressing A's toast brought A forward on that server with #general open. Then with A quit: pressing the toast started `rift.exe --rift-profile=wa -Embedding` (Windows, through the registered activator), which opened as A, waited for the vault and opened #general at the mention. A probe toast for A, pressed while B also ran, went to A, not B. Before: no press reached the app. Later the same day: a server DM toast (it shows the message text) and the same toast's entry in the notification centre after its banner was closed each brought A forward from minimised with the DM open. A DM call's toast, pressed while ringing, brought A forward with the ringing card, and Answer connected. A Rift DM toast switched A from the server to Direct messages with that conversation open. Not driven: the installed build, and Linux/macOS |
| Pressing a message notification (Linux) | Oct 2 2026 | GNOME, release bundle, Lana (`e2e_a`) and Benny (`e2e_b`) on one PC; the user clicked the banners, the `Notify` calls and the `default` action were watched with `dbus-monitor`. Benny @mentioned Lana in #general while she had no channel open and was behind his window: the press opened #general at the mention. With Lana minimised on #general, a server DM's press brought her window back (Normal, focused) with the DM open; again from no channel selected. Also Oct 2, by the user: a server DM's entry pressed in GNOME's notification list 52 s after the banner (Lana minimised) brought her window back with the DM open at the message. GNOME draws no "Open" button — the notification's only action is `default`, which is the banner body — so there is no button to press. With Lana closed after the notification arrived, pressing it sent `ActionInvoked` to her vanished D-Bus name: nothing started, and GNOME dismissed the notification. (Windows launches the app from a toast; Linux would need the `desktop-entry` hint and an activatable desktop file.) |
| Secure storage in Local AppData, per profile (Windows) | Oct 1 2026 | Windows 11, debug build, profiles wa and wb: on first launch each moved only its own keys from the old Roaming `flutter_secure_storage.dat` into `rift_<profile>\secure_storage.dat` under Local AppData and opened its vault with both servers; the Roaming file kept the other profiles' keys untouched; A restarted and opened its vault from the new file alone. Key names checked with a DPAPI script that prints names only. The release default (no profile) and the file being deleted once empty were not driven live; both are unit-tested |
| Profiles side by side keep their own central sign-in (`RIFT_PROFILE`) | Oct 1–2 2026 | Windows 11, two profiles on a local central: the existing session moved from the shared preferences file into the profile's own `central_auth.json` on launch (B stayed signed in); A signed in while B ran, then A was restarted and stayed signed in — before, B's next write had erased A's session twice in one evening. Linux not driven. Linux, Oct 2: a session under the old shared key moved into `rift_<profile>/central_auth.json` on launch and the profile stayed signed in; two profiles signing in side by side not repeated there |
| Settings mic test outside a call | Oct 1–2 2026 | Windows 11, no call: Test mic opened the chosen input (Windows' audio sessions showed Rift recording from it) and the meter followed a phrase played into a virtual cable (10 of 24 bars) and the laptop mic hearing the speakers (4 bars); switching the input while testing moved the test to the new device; Stop released the mic. It used to stay dark with no microphone opened. In a call the test still reads the call's own levels. Linux (GNOME, PipeWire), Oct 2, with a PulseAudio test source fed a voice-like signal: on the WebRTC path the meter stayed dark and no record stream was opened, as on Windows; now the test opens the input itself (`pactl list source-outputs`: on "System default" a stream with no device named, on the default mic; picking the test source mid-test moved it there), the meter read 10–16 of 24 bars with the signal and none with the source measured silent (-120 dBFS), and Stop left no stream. With the saved input unplugged (picker showing "System default") the test failed with "Could not access the microphone" until Oct 2; it now opens the default, verified on Linux. macOS keeps the WebRTC path (untested) |
| Choosing the input and output device outside a call | Oct 1 2026 | Windows 11: Settings → Voice & audio with no call up now lists Windows' devices (it used to say "No devices found"); the laptop mic and a virtual cable picked there were what the client recorded from and played to on joining (read from Windows' audio sessions), and "System default" picked there moved both back to Windows' defaults on the next join. Picks in a call still apply at once. Linux, Oct 2: WebRTC itself lists the devices before the first call (its libwebrtc since m150 starts the device module with the factory), but not after a call ends — leaving terminates the module until the next call, which the first pass missed and the user found with a headset. The pickers then read PulseAudio through the Rust library, under WebRTC's ids (the description); a Bluetooth headset picked that way was what the client recorded from on the next join. WebRTC's extra "default: …" entry is hidden and is now what "System default" selects. A test source and a test sink picked outside a call were what the client recorded from and played to on joining; a sink added and then removed with Settings open appeared and disappeared without reopening the list, in a call too (Rift watches PulseAudio itself: WebRTC sends no device changes on Linux). macOS not driven |
| A Windows mic staying alive after the last other voice leaves (and after deafening) | Oct 1 2026 | Windows 11, two clients, the other side's voice measured on the speakers. Before: A unmuted, B (with a published mic) leaves for 15 s and rejoins — A sent digital silence until A rejoined ("capturing thread has ended prematurely" in A's WebRTC log). After: the same, plus A muted while B leaves (unmutes alone, or after B is back) and A deafening for 10 s — A heard every time (-17 to -31 dBFS), the mic republished once each time, no capture death logged. Output switching mid-call while unmuted also kept A's mic. Linux and macOS do not use this path. Linux, Oct 2, the same leave (B unmuted, out for 15 s) with A's voice measured at B's output: heard at -11 and -9 dBFS after B rejoined — the bug does not exist there |
| Picking the input and output device in a call, and going back to "System default" | Oct 1–2 2026 | Windows 11, two clients; which device each process actually had open read from Windows' audio sessions. Input (first-listed input a virtual cable, Windows' default the laptop mic): picking the laptop mic mid-call, then a mute and unmute, a leave and rejoin, a switch while muted, "System default" from the cable, and a fresh launch on "System default" all kept or moved capture to the right device (each used to end up on the first-listed input). Output: "System default" from a virtual cable moved playout back to the speakers mid-call, and the other client's voice measured there at -17 dBFS (it used to stay on the cable until a restart). macOS not driven. Linux, Oct 2, two clients (which device each process recorded from and played to, `pactl list source-outputs` / `sink-inputs`; the other client's hearing measured on its test sink): a picked test input stayed in use through mute and unmute and through a leave and rejoin. "System default" mid-call moved capture back to the default mic and playout back to the speakers, with no device named, so changing the default mic and speaker in the desktop's settings then moved the running call with them (and the other client heard the new mic); it stayed on the default through a mute and unmute and a leave and rejoin. Before that day's fix it stayed on the picked device until a restart. Also Oct 2, driven by the user: two wired headsets, switching the default between them in GNOME during a call — audio followed each switch both ways; and unplugging the headset in use mid-call carried the call on without a rejoin |
| "Can't reach <server>" chip in the desktop title bar (the selected server's socket down; "No internet" takes its place when offline) | Oct 1–2 2026 | Windows 11, `docker stop rift-kong` with a client on the server: the red chip appeared 5 s after the stop (the settle) and was gone 3 s after Kong started again, when the socket reopened (title bar recorded every second). Precedence and switching servers covered by widget and cubit tests only; Linux, macOS and phone layouts not driven. Linux, Oct 2: appeared while `rift-kong` was stopped and cleared when it was back |
| "No internet" chip in the desktop title bar | Oct 1 2026 | Windows 11, real Wi-Fi off for ~16 s: the chip appeared 2 s after the drop (the settle), stayed while off and was gone within a second of Wi-Fi coming back (title bar recorded every 2 s); WSL's virtual switch and Tailscale, still up, did not count as online. Linux (Oct 2, GNOME 50, NetworkManager): the chip never showed at first — with Wi-Fi off, Tailscale and loopback stay up, so NetworkManager says `limited`, not `none`, and connectivity_plus counted that as online. Now read from NetworkManager directly (`LinuxConnectivity`): two clients with real Wi-Fi off for ~9 s, the old build showed nothing and the new one "No internet" 5 s in; gone 5 s after Wi-Fi came back. macOS and phone layouts (no title bar) not driven |
| Reopening the desktop window on a screen that exists (size and place fitted to the work area) | Oct 1 2026 | Windows 11, one 1920×1080 display: a client saved at 1280×720 logical at 100 % reopened at 150 % fitted to the work area instead of past the edges and under the taskbar; at 100 % three clients reopened where they were. Unplugged or mixed-scale second monitors not tried (no second monitor). Linux (Oct 2, GNOME 50, one 1920×1080 display): the saved geometry was edited while the client was closed. Half off the right edge (x 1500, 900 wide) reopened at x 1020; 2600×1500 (the scale-change shape) reopened at 1920×1048 under the top bar; at (3000, 2000) (the unplugged-monitor shape) reopened at (1020, 380) keeping 900×700, and drew normally. GNOME does the same to any X11 window on its own — a plain GTK window asked for those places landed in the same spots — so on GNOME this proves the outcome, not that Rift's fitting is what produced it |
| Conversations saved on the device: drawn on open, offline, replaced by the fresh page | Oct 1–2 2026 | Windows, two clients, gateway stopped: channels and server DMs, a row deleted while closed, own messages; the server DM list now loads by itself when the server comes back after an offline start (it used to stay empty). Wipes on leaving a server and on a vault reset, files unreadable, pruning a deleted channel. Central DMs and the sign-out wipe not driven. Linux, Oct 2: the server DM list after an offline start loaded by itself once the gateway was back, with no click. Own sends now reach the copy on quitting and on clicking away (Linux release, Oct 2, Kong paused before reopening the DM): a DM sent and then the window closed through the window manager's close request showed in the offline copy; one sent, then #general clicked with the DM still open behind, then the app killed with `kill -9`, showed too. The user then quit by hand on the release build with the tray's Quit, and with GNOME's close-window key (Super+Q here; Alt+F4 is not bound) while that still quit — it now hides to the tray |
| One-to-one calls in server DMs | Sep 27 2026 | two clients + Android; ringing, answer from anywhere, decline, missed, audio both ways recorded, tracks encrypted |
| The tray menu and quitting (Linux) | Oct 2 2026 | GNOME 50 with the AppIndicator extension, release build, two clients: clicking the icon opens Show Rift / Quit (it opened nothing before — the item advertised no menu until its trigger was set to clicked), and Quit exits; GNOME's close-window key (Super+Q here) hid the window at once and the app exited (pressed by the user). Since Oct 2 the desktop's close hides to the tray like the title bar's button, and only the tray's Quit exits: a close request left the process running with the window hidden, the menu's Show Rift brought it back, Quit exited (driven over DBus and a `_NET_CLOSE_WINDOW` message, not by hand). Not checked on Windows |
| Accepting a DM request opens the sender's composer | Oct 2 2026 | Linux release, Lana and Benny with Benny on "Ask me first": Lana's first DM waited with her composer locked; Benny pressed Accept and within 2 s Lana's composer opened and the call button appeared, without reopening the conversation (it used to stay locked) |
| A refused message comes back to the composer | Oct 2 2026 | Linux release, Lana and Benny: Benny blocked Lana in the database, Lana sent him a server DM — "Benny isn't accepting messages from you right now" and her words were back in the field (they used to be lost). Channels and Rift DMs take the same path (`composer_give_back_test.dart` covers the composer); only the server DM was driven |
| A bot's new command reaches a channel that is already open | Oct 2 2026 | Linux release, Lana in #general with the `/` menu showing echo's three commands: a fourth added to echo's manifest in the database showed in the menu 3 s later without reopening the channel, and sending it stored a plaintext command addressed to echo (key version 0), not sealed text. Before, it needed the channel reopened. Not driven: a real bot republishing, or a private channel |
| A privacy-mode vault signed in to an account, then signed in again | Oct 2 2026 | Linux release on a local central: a fresh profile made a vault with its own password in privacy mode, then created an account ("Account connected. Backup saved."). With only its central session deleted it signed in again and went straight to "Account connected. Backup saved." — no "Two identities" question. A second fresh profile signing in to the account restored without asking for the vault password ("Backup restored from your account."). The old build was not re-run for comparison; before, the first question was unconditional and the second followed from the uploaded seed blob |
| Kicking a member, and their way back | Oct 2 2026 | Linux release, Lana (owner) and Benny in #general: Kick on Benny while he held Moderator was refused ("Somebody who can kick or ban cannot be kicked"). With a plain role instead, Kick → Benny's window turned to "You were removed from Rift Test", his role was gone, and Lana's profile and Members list said "Kicked" with Ban offered (no Kick, no Lift ban). A one-use invite carrying a role, pasted into Benny's Join server with a new username typed: "Welcome back to Rift Test — you are Benny again", the old name kept, the invite's role granted, the invite spent, the history readable, and a new message from him read by Lana under the current key. Not driven: a kick during a call (the removal from LiveKit is ban's path), a Moderator rather than the owner pressing it (the schema suite covers that), the phone layout |
| Narrowing the desktop window with a server DM open behind a channel | Oct 2 2026 | Linux release: DM open, #general clicked, window narrowed to 640: #general stayed on screen (the DM used to be pushed over it); back, Direct, Benny opened the DM normally |
| Server moderation: reports, time-outs, bans, DM requests, blocks | Sep 27 2026 | two clients + headless members; security pass probed the database and realtime directly |
| Wording and UI for moderation and DM calls | Sep 27 2026 | two clients; the time-out menu and banner, including expiry |
| Directory moderation (`rift-admin`) | Sep 26 2026 | local central; second factor enforced, lockout after five wrong codes |
| Central's own stack, backups and restore | Sep 26 2026 | local stack; encrypted backups to a stand-in S3 bucket, then a wiped stack restored with every account, vault and attachment intact |
| Web build | Sep 26 2026 | Chrome, before deploying |
| Reactions and pins after their read rules were rewritten | Oct 2 2026 | two clients (Lana, Benny) after `message_reactions_select` / `message_pins_select` stopped calling `app.can_see_message` per row: #general's page loaded (`channel_messages` with reactions embedded, 200); a 🎉 from Lana appeared on Benny's screen live, Benny's own made it 2 on both; reopening the channel refetched the page and still showed 2; a new pin appeared in Benny's pins panel beside the seven older ones. Private channels and bots were checked in the schema suite and against the live rows, not in the app |
| Pins and polls | Sep 26 2026 | two clients |
| Voice regions: pinning, moving a live call, a region dying | Sep 25–26 2026 | two clients on two LiveKits on one machine |
| Roles, bans, bots in a call | Sep 23 2026 | a clean stack driven end to end |
| Safety codes | Sep 22–23 2026 | two clients, both ends |
| A DM whose key no longer opens it shows its messages locked | Oct 2 2026 | Linux release, Lana with Benny's key swapped in the database: every message showed as a locked row with author and time (they used to vanish), the DM list read "Message you cannot open yet"; with his key back they opened again. Channels and Rift DMs take the same path (`sealed_open_test.dart`); only the server DM was driven |
| A DM saying the other person's key changed | Oct 2 2026 | one client, the peer's key swapped in the database: amber chip, a line per change, cleared by looking or verifying; held amber for a verified person; desktop and phone width. Central DMs and the profile's line not driven |
| Screen share, including a phone's stream | Sep 22 2026 | Linux sharing, desktop and Android watching |
| Push-to-talk on Linux | Sep 21 2026 | GNOME, through the GlobalShortcuts portal |
| Server rail order across devices | Sep 21 2026 | one account on two devices, and a reorder made offline |
| Soundboard | Sep 20–21 2026 | two clients in a call |
| Replies, forwarding, jumping to a message | Sep 20 2026 | two clients, channel to channel |
| People profiles | Sep 20 2026 | both tiers |
| Bot directory | Sep 20 2026 | publish, browse, like, add |
| Operator limits | Sep 19 2026 | two clients; each cap refuses and says why |
| A server built from nothing, with a bot | Sep 6 2026 | the console's stack, two clients, a bot through the SDK |
| Encrypted voice, audio both directions | Sep 2 2026; Sep 30, Oct 2 2026 | two clients on virtual microphones, a key rotation mid-call; on Sep 30 (Windows) one minted by a client in the call, which has to move its own call too. On Oct 2 (Linux) a ban rotated the key from a client in the call and both calls logged the move to the new version; audio not measured that time |
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

**Servers and moderation**
- An open profile doesn't refresh live ("Timed out until…" stays after it ends), and
  Manage server → Members' count lags right after a ban is lifted.
- Choosing "Only @mentions" for a channel while its server is on the default stores
  nothing (it equals the default), so switching the server to All later carries
  the channel along. By design per `_setLevel`; still surprising.

**Voice and calls**
- Rift's own sounds (the ring) play on the system default output, not the output
  chosen in Settings.
- A shared window that is minimised freezes on its last frame for viewers, with no
  hint that it's paused (Windows sends no frames for a minimised window).
- Once, the speaking glow didn't light for about ten minutes although audio
  flowed. Not reproduced.

**Keyboard and accessibility**
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
- Linux, Oct 2: the first time the other side unmutes after you join, your voice
  often drops out for them for one to two seconds (three tries in four, measured
  at -50 to -70 dBFS against -10 to -20 either side). Not seen on later unmutes,
  nor in the one try with your echo cancellation off, so it looks like WebRTC's
  echo canceller adapting as the far end starts; Windows uses the system's
  canceller instead. Not chased.
- Linux, Bluetooth headsets: changing the default device mid-call can leave the
  call silent until it is rejoined. Seen Oct 2 with an Arctis Nova Pro Wireless
  over Bluetooth. Its mic needs the headset profile (HFP), each switch flips it
  between that and A2DP, and PipeWire logged "Failure in Bluetooth audio
  transport" repeatedly; at times the mic gave no data even to `parec`, outside
  Rift. Two wired headsets switched cleanly, so this looks like the Bluetooth
  stack, not Rift. Not ruled out: Rift's stream staying silent once the
  transport recovers (seen once, with the transport still flapping).
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
