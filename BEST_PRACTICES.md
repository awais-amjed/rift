# BEST_PRACTICES.md — state, Bloc and Flutter rules

The rules Rift follows for where state lives and how it moves, taken from the
Bloc library's docs, Flutter's architecture and performance guides and Effective
Dart (sources at the end), and adapted to this app. `AGENTS.md` says how Rift is
laid out and `CODE_STYLE.md` how files are sized and split; this file says how
data gets from the server to a pixel and back without being copied, forgotten or
drawn stale.

Where Rift deliberately differs from a source, the rule says so and why.
Existing code that breaks a rule is fixed when it is touched, like the size
budgets in `CODE_STYLE.md`; new code follows the rule from the start.

## 1. Layers, and who may talk to whom

```
widgets  →  cubits  →  repositories  →  network / storage / platform
   ↑           │
   └── state ──┘
```

- **Data flows one way.** State comes up from a cubit; user actions go down as
  calls on it. A widget never calls a repository, never does I/O, and never
  changes data in place.
- **Each layer talks only to its neighbours.** Widgets don't know repositories
  exist; repositories don't know cubits or widgets exist and never emit.
- **A cubit learns things only from its own method calls and from the
  repositories it was given** (Bloc docs: "no bloc should know about any other
  bloc"). See §3 for what to do when two cubits need the same thing.

## 2. One source of truth

- **Every piece of data has exactly one owner, and only the owner changes it.**
  The owner is a cubit (backed by a repository). Every widget that shows the data
  selects it from that cubit's state. Change it there and it changes everywhere.
- **Never copy shared data into a widget.** A widget that fetches something in
  `initState` and holds it in `setState` has made a second copy that nothing else
  can see or update — a failure in it sticks, and a change elsewhere never
  reaches it. That is the avatar bug of Oct 8 2026.
- **Is it app state or widget state?** It belongs in a cubit if *any* is true:
  - a second widget shows it, or could;
  - something outside the widget can change it (another device, realtime, a
    token refresh, another screen);
  - it should outlive the widget (closing a panel, scrolling a row away).

  Otherwise `setState` is right and a cubit is overkill: hover, open/closed, a
  tab index, an animation's progress, a form's draft text and its "saving…"
  flag. Flutter's own rule of thumb is "do whatever is less awkward" — the test
  above is how to tell which that is.
- **A cache the UI reads is state.** It lives in a cubit's state (or behind a
  repository stream a cubit listens to), never in a singleton widgets look into.
  A singleton has no way to tell a waiting widget that the thing it wanted has
  arrived.
- **Loading is part of the state, per item.** Something fetched carries its
  status — not loaded, loading, loaded, failed — beside its value, so the UI can
  draw each, and a failure is an entry that can be retried rather than a widget
  that gave up.
- **Store what can't be computed; derive the rest with getters.** Two fields
  that must be updated together will one day not be.

## 3. When cubits need each other

- **Don't add a cubit-to-cubit reference.** The Bloc docs' reason: siblings that
  know each other are tightly coupled, and a change in one breaks the other.
  Many cubits predate this file and take others — `VaultCubit`, `AppCubit`,
  `LiveKitCubit` — through their constructors or an `inject…` setter
  (`grep -rnE "final \w+Cubit\??\s+_?\w+;" lib/logic/cubits`). Leave
  those until the work in question touches them; don't add new ones. For the
  selection and a token, take `SessionRepository`, and for a server's calls the
  feature's class in `data/apis/` built on it. The session also holds each
  server's one Realtime connection (`realtime`) and says when the list or the
  selection moved (`changes`), which is all `ServerTopicWatcher` needs.
- **Instead, push it down or up:**
  - *Down* — both cubits take the same repository, and the repository exposes a
    `Stream` of the shared data. Each cubit subscribes and keeps its own state.
    Use this when the data is shared (the signed-in user, a server's roles).
  - *Up* — a `BlocListener` on cubit A calls a method on cubit B. Use this for
    a one-off reaction (leaving a server closes its call).
- **No public fields on a cubit** (bloc_lint `avoid_public_fields`). Private
  working data — keys, caches, requests in flight — may live in private fields.
  If a widget draws it and it can change, it goes in `state`: a getter on the
  cubit hands over the value of that moment, and only an emit rebuilds.
- **Results come back through state.** bloc_lint's `prefer_void_public_cubit_methods`
  wants every public cubit method to return `void`/`Future<void>`. Rift differs
  in one case: a method a dialog calls may return the *outcome* of that action
  (`({bool success, String? error})`) so the dialog can show the error or close.
  It never returns *data* another widget needs — that goes into state.

## 4. State classes

- **Immutable.** `final` fields, a `const` constructor, a `copyWith`. Never
  mutate a list or map held in state; build a new one and emit it.
- **Value equality on every state and every model, over every field.** `emit`
  drops a state equal to the current one, and `buildWhen`, `listenWhen` and
  `BlocSelector` decide with `==`. Without `==`, every equal copy looks new and
  rebuilds; with a field left out of it, a change to that field compares equal
  and the screen keeps the old value. Use `Equatable` and list every field in
  `props`; `test/value_equality_test.dart` reads the source and fails on a class
  without equality or a field missing from it. A set goes in as `SetProp`
  (Equatable compares sets in quadratic time) and bytes as `IdentityProp`
  (`data/classes/equality_props.dart`). Hand-write `==` and `hashCode` together
  only where identity is the point (`MediaEntry`), and only on immutable classes.
- **Status names:** a status enum with `initial, loading, success, failure`, or
  sealed subclasses ending in `Initial`, `InProgress`, `Success`, `Failure`
  (Bloc naming conventions). Not `Loaded`, `Done`, `Error`.
- **Cubits stay free of widgets.** No `package:flutter/material.dart` in
  `logic/cubits/`; `foundation.dart` (`kIsWeb`, `listEquals`) and `dart:ui`
  (`Size`, `Offset`) are fine. The theme cubit, which hands out `ThemeData`, is
  the one exception.

## 5. Reading state in widgets

- **`context.read` only in callbacks** (`onPressed`, `initState` actions) —
  never to read state in `build`, where nothing rebuilds the widget when the
  state changes.
- **Watch the smallest slice, as low in the tree as it is used.** Prefer
  `BlocSelector` or `BlocBuilder` with `buildWhen` around the widget that uses
  the value; `context.watch`/`context.select` at the top of a large `build`
  rebuilds all of it. (Rift's hot paths already depend on this — `AGENTS.md`,
  *Presentation*.)
- **Builders are pure.** A `BlocBuilder`'s builder runs many times; it returns a
  widget and does nothing else. Toasts, navigation and dialogs are shown by the
  callback that made the call and got its outcome back, or by a `BlocListener`
  (`listenWhen` to filter) — never by a builder, and never by the cubit itself
  (`CODE_STYLE.md` §8). `BlocConsumer` only when one widget needs both.
- **Who creates a cubit closes it.** `BlocProvider(create:)` makes and closes
  it; `BlocProvider.value` passes one that already exists (dialogs, new routes)
  and leaves it open. Never construct a cubit in `build` or for a dialog.

## 6. Async and lifecycle

- **After every `await` in a widget, check `mounted` (or `context.mounted`)**
  before touching `context` or `setState` (lint `use_build_context_synchronously`).
- **After an `await` in a cubit, check the answer is still wanted** — a slow
  reply for the previous server must not land on the current one — **and, in a
  cubit that can close before the app does, check `isClosed` before `emit`**
  (`CODE_STYLE.md` §8 has the detail).
- **A cubit cancels what it started.** Stream subscriptions, timers and
  listeners are cancelled in `close()`.
- **Fire-and-forget is written down:** `unawaited(...)`, never a bare future.
- **Errors from a repository become state or an outcome**, never an uncaught
  exception in a widget. Don't catch `Error` (it is a bug); `rethrow` to pass an
  exception on (Effective Dart).

## 7. Building widgets cheaply (Flutter performance guide)

- `build` runs often: no work in it that could be done once. Split a widget by
  what changes together, and keep `setState` in the smallest widget that needs it.
- `const` constructors wherever possible — Flutter skips rebuilding them.
- A reusable piece of UI is a widget class, not a method returning a widget.
- Long or unbounded lists use a `.builder` constructor, never a `Column` or
  `ListView(children:)` of everything.
- Avoid the `Opacity` widget: draw in a colour with alpha, or use
  `AnimatedOpacity`/`FadeInImage`. Clip only when needed, and prefer a
  `borderRadius` to a clip. `ShaderMask`, `ColorFilter` and `Clip.antiAliasWithSaveLayer`
  allocate an offscreen layer; use them knowingly.
- In `AnimatedBuilder`/`TweenAnimationBuilder`, pass what doesn't animate as
  `child` so it is built once.
- Never override `==` on a `Widget`.
- Join many strings with a `StringBuffer`, not `+` in a loop.
- Measure in profile mode, not debug.

## 8. Dart (Effective Dart, the rules that bite)

- Fields and locals `final` by default; constructors `const` when they can be.
- `Future<void>` for async work with no result; `async`/`await` over `.then`
  chains; no `Completer` unless bridging a callback API.
- No positional `bool` parameters — name them.
- Don't return a nullable `Future`, `Stream` or collection; return an empty one.
- Curly braces on every `if`/`for` body.
- Doc comments (`///`) start with a one-line summary; say *why*, per `AGENTS.md`.

## 9. Enforcing it

`flutter analyze` with `flutter_lints` already catches §6's context rule and
most of §8. The Bloc rules in §3–§4 can be checked by `bloc_lint`'s recommended
set (`avoid_flutter_imports`, `avoid_public_bloc_methods`, `avoid_public_fields`,
`prefer_file_naming_conventions`, `prefer_void_public_cubit_methods`), run as
`bloc lint .` — not enabled yet; it would need the Rift exceptions above
switched off.

## Sources

Read Oct 8 2026.

- Bloc — [Architecture](https://bloclibrary.dev/architecture/),
  [Bloc concepts](https://bloclibrary.dev/bloc-concepts/),
  [Flutter Bloc concepts](https://bloclibrary.dev/flutter-bloc-concepts/),
  [Naming conventions](https://bloclibrary.dev/naming-conventions/),
  [Lint rules](https://pub.dev/documentation/bloc_lint/latest/)
- Flutter — [Architecture concepts](https://docs.flutter.dev/app-architecture/concepts),
  [Architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations),
  [Ephemeral vs app state](https://docs.flutter.dev/data-and-backend/state-mgmt/ephemeral-vs-app),
  [Performance best practices](https://docs.flutter.dev/perf/best-practices)
- Dart — [Effective Dart](https://dart.dev/effective-dart)
