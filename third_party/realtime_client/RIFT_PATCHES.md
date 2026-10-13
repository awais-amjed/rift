# realtime_client, kept here and patched

Supabase's Realtime client for Dart, `realtime_client` 2.13.2, taken from the
`realtime_client-v2.13.2` tag of
[supabase/supabase-flutter](https://github.com/supabase/supabase-flutter)
(commit `610e9d37e2f3`, MIT — see `LICENSE`). Only `lib/` and the licence are
kept; the `pubspec.yaml` is upstream's without the workspace resolution and the
dev dependencies. The app uses this copy through `dependency_overrides` in its
own `pubspec.yaml`, so `supabase` and `supabase_flutter` stay on pub.dev.

Every change in `lib/` is marked `RIFT PATCH`; a diff against the release on
pub.dev shows all of them.

## Why

After a gateway outage on Oct 2 2026 (Linux, two clients) both clients came back
connected but deaf: their `server:`, `user:` and open `chat:` topics sat
"joining" and were no longer in the socket's channel list, so nothing arrived
live until a restart. It happened once in nine outages: it is a race.

Every failed reconnect armed each channel's rejoin timer. When the socket
reopened, the client rejoined the channel at once, and the timer then fired
while that join's reply was still on its way. `rejoin()` asked the socket to
leave any other channel on the same topic that was joining or joined, and the
one it found was itself. That is supabase-flutter issue #568 (2023).

Upstream fixed most of it in October 2026: 2.13.1 (#1933) sends a resent join
with a fresh ref and removes only the given channel, and 2.13.2 (#1950) keeps a
rejoin from leaving itself and holds back a rejoin while a join awaits its
reply. What it still does differently from phoenix.js, which this client ports,
is arm the rejoin timer while the socket is down. That timer fires at some
arbitrary moment after the reconnect and cuts short a slow join still waiting
for its reply.

## The patches

All three are in `lib/src/realtime_channel.dart`, as phoenix.js does it:

1. **A channel's error handler resets a join in flight** (`joinPush.destroy`),
   so the rejoin sends a fresh one.
2. **The error handler arms the rejoin timer only over a live socket**, and
   resets it otherwise. A dead socket rejoins every errored channel itself when
   it opens (`_onConnOpen`).
3. **A join timeout arms it only over a live socket** too.

## How it was checked

- `test/realtime_client_patches_test.dart` in the app. Its last case, "a dropped
  socket arms no rejoin timer…", fails on the 2.13.2 release (measured Oct 13
  2026); the others failed on 2.13.0 and pass on 2.13.2 unpatched.
- Upstream's own unit suite for 2.13.2 (`dart test -x integration` in the
  package, with `lib/` replaced by this one) passes unchanged, Oct 13 2026. The
  integration tests need the Supabase CLI's local stack and were not run.
- Live, against the local stack: see `TESTING.md`. That was the earlier copy,
  2.13.0 with these three patches and the four upstream has since taken.

## When this can go

When a `realtime_client` release arms no rejoin timer over a dead socket and
`test/realtime_client_patches_test.dart` passes on it without this copy. Delete
this folder and the override, and keep the test: it is the check that the
release really has the fix. Until then, a change to this copy goes here with a
line above saying why.
