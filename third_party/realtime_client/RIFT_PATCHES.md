# realtime_client, kept here and patched

Supabase's Realtime client for Dart, `realtime_client` 2.13.0, taken from the
`realtime_client-v2.13.0` tag of
[supabase/supabase-flutter](https://github.com/supabase/supabase-flutter)
(commit `5be5a16228ae`, MIT — see `LICENSE`). Only `lib/` and the licence are
kept; the `pubspec.yaml` is upstream's without the workspace resolution and the
dev dependencies. The app uses this copy through `dependency_overrides` in its
own `pubspec.yaml`, so `supabase` and `supabase_flutter` stay on pub.dev.

Every change in `lib/` is marked `RIFT PATCH`; `git diff` against the commit
that brought the copy in shows all of them.

## Why

After a gateway outage on Oct 2 2026 (Linux, two clients) both clients came back
connected but deaf: their `server:`, `user:` and open `chat:` topics sat
"joining" and were no longer in the socket's channel list, so nothing arrived
live until a restart. It happened once in nine outages: it is a race.

Every failed reconnect armed each channel's rejoin timer. When the socket
reopened, the client rejoined the channel at once, and the timer then fired
while that join's reply was still on its way. `rejoin()` asks the socket to
leave any other channel on the same topic that is joining or joined — and the
one it found was itself. It unsubscribed itself, which takes a channel off the
socket's list, and sent a join whose reply nothing on the socket could hear.
That is supabase-flutter issue #568 (2023, closed without a cause found).
phoenix.js, which this client ports, does not do this: it arms the rejoin timer
only over a live socket and resets it when the socket opens or errors.

## The patches

1. **`RealtimeClient.remove` matches the channel itself**, not its `joinRef`,
   which is empty until a join is sent — removing one unsent channel removed
   them all. Upstream #1669, in `supabase_realtime` 3.0.0-dev.1.
2. **`Push.resend` cancels the pending timer.** With it still running,
   `startTimeout` returned early and the join went out with an empty ref that
   no reply matched. Upstream #1822, in `supabase_realtime` 3.0.0-dev.3.
3. **A channel's error handler resets a join in flight** (`joinPush.destroy`),
   as phoenix.js does.
4. **It arms the rejoin timer only over a live socket**, and resets it
   otherwise. A dead socket rejoins every errored channel itself when it opens
   (`_onConnOpen`). As phoenix.js.
5. **A join timeout arms it only over a live socket** too.
6. **The rejoin timer does not re-arm itself.** It fired again while the join it
   had just sent was in flight. A failed join re-arms it (timeout, error), and a
   reopening socket rejoins errored channels. As phoenix.js.
7. **`leaveOpenTopic` never matches the channel asking**, so no rejoin can leave
   itself — including the one `_handlePresenceUpdate` makes on a joined channel.

Patches 3 to 7 are not upstream: `main` still has the self-leaving rejoin as of
Oct 2 2026.

## How it was checked

- `test/realtime_client_patches_test.dart` in the app: five cases, four of which
  fail on the 2.13.0 release.
- Upstream's own unit suite (`dart test -x integration` in the tag's package
  directory, with `lib/` replaced by this one): 183 pass. One test changed its
  expectation: "correct CHANNEL_ERROR data on heartbeat timeout" expected
  `closed` after the error, and that `closed` was the channel leaving itself as a
  duplicate of its own topic (traced: "leaving duplicate topic" three seconds
  after the error). Patched, it stays on the socket and rejoins. The
  integration tests need the Supabase CLI's local stack and were not run.
- Live, against the local stack: see `TESTING.md`.

## When this can go

When the app moves to a `supabase_realtime` release that has #1669, #1822 *and*
a fix for the self-leaving rejoin (patches 3–7). Delete this folder and the
override, and keep `test/realtime_client_patches_test.dart`: it is the check
that the release really has them. Until then, a change to this copy goes here
with a line above saying why.
