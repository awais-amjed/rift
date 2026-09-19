# AGENTS.md — Rift coding conventions

Rift is a self-hostable Discord alternative: Flutter (UI, all platforms) + Rust (screen capture
pipeline via flutter_rust_bridge) + Supabase (self-hostable backend: Postgres, Edge Functions,
Storage) + LiveKit (voice/video). Design goals: clean minimal UI, maximum use of space (every
piece of chrome can collapse/hide), fast native screensharing.

These conventions are extracted from the existing code. Match them; don't introduce parallel
patterns. For the shape of the system and the reasoning behind it, see `ARCHITECTURE.md` — an
overview, so read it before touching vault, auth, backup or messaging code, and follow it to
`WIRE.md` for a format, to a migration for what the server stores, or to `API.md` in
`rift-self-host` for an endpoint.
**`CODE_STYLE.md` covers file size budgets, one-widget-per-file, extracting shared logic, and
central constants — read it before adding to an existing file or copying a block of code.**

## Layout

```
lib/
  data/           # No Flutter UI imports here
    classes/      # Plain immutable models
    enums/        # Enums with fromString/toJson helpers
    repositories/ # All external I/O: HTTP, Supabase, crypto, secure storage
    constants.dart# `K` class — layout constants (sizes, paddings)
  logic/
    cubits/       # One folder per feature: foo/foo_cubit.dart + foo_state.dart
    services/     # Platform services (sound, Windows audio ducking)
    ptt/          # Push-to-talk key listener
    helper_methods.dart  # HelperMethods: toasts, navigation, printDebug
  presentation/
    common/       # Shared widgets (AppModal, AppTitleBar, ...)
    routing/      # go_router setup (AppRoutes)
    screens/      # Folder per screen; nested feature folders with widgets/ subfolders
    theme/        # app_palette.dart + palettes/ (themed colors), app_text.dart (type),
                  # app_shadows.dart (depth), custom_colors.dart (status colors)
  src/rust/       # GENERATED flutter_rust_bridge bindings — never edit by hand
rust/src/api/     # Rust API surface exposed to Flutter — bridge functions and types only
rust/src/screenshare/  # What those functions call: session, capture, audio/ per platform
server_migrations/  # Numbered SQL migrations (001_..., 002_...)
```

## State management — Bloc/Cubit only

- One cubit per feature under `lib/logic/cubits/<feature>/`. No Provider, Riverpod, setState-based
  app state, or singletons for shared state.
- **Persisted state** → `HydratedCubit<State>`; **ephemeral state** → plain `Cubit<State>`.
- State classes live in a `part` file (`foo_state.dart`, `part of 'foo_cubit.dart';`). They are
  immutable, with `const` constructors where possible, a `copyWith`, and for hydrated cubits
  `@JsonSerializable` + generated `_$FooStateFromJson/ToJson` (run
  `dart run build_runner build` after changing them — `.g.dart` files are committed).
- Transient fields inside a hydrated state are excluded with
  `@JsonKey(includeFromJson: false, includeToJson: false)` and grouped under a
  `// ── Transient ──` banner, persisted fields under `// ── Persisted ──`.
- Clearing a nullable field goes through an explicit flag param in `copyWith`
  (e.g. `copyWith(clearPushToTalkKeybind: true)`), never `null`-means-clear.
- **Large cubits are split into `part` files with private mixins**: `server_cubit.dart` +
  `server_crud.dart` / `server_selection.dart` / `server_api.dart`, each defining
  `mixin _ServerCrudMixin on Cubit<ServerState>` with abstract getters for shared dependencies.
  Follow this pattern instead of letting a cubit file grow past a few hundred lines.
- Cross-cubit dependencies are injected after construction via an explicit setter
  (`injectVaultCubit(...)`) to avoid circular construction — not via service locators.
- Cubits never do I/O directly; they call repositories (`ServerRepository`, `CryptoRepository`,
  `SecureStorageRepository`, ...). Repositories never emit state.

## Data layer

- Models in `data/classes/` are plain Dart: final fields, `const` constructor, hand-written
  `fromJson`/`toJson` with **snake_case JSON keys matching the server** (`channel_type`).
  `@JsonSerializable` codegen is used for cubit states, not for these API models.
- Multi-value returns use records:
  `Future<({bool success, String? content, String? error})>`.
- All Edge Function calls return the shared `APIResponse` (mirrors the
  `{success, data, error, code}` envelope). Check `response.success`; never assume HTTP errors —
  the API always returns 200.
- Session (JWT) expiry is handled centrally by `ServerCubit._callWithAutoRefresh` (a silent SIWS
  re-login); new API calls must go through it rather than re-implementing refresh/retry.
  It runs against the selected server; `_callFor(server, …)` is the same thing for a **named**
  server. An API call a dialog can open for a server other than the current one takes an
  optional `serverId` and resolves it with `_target()` — reading `state.selectedServer` inside
  such a call is how a form ends up writing to the wrong server.
- Enums carry their own `fromString` / `toJson` conversions (see `channel_type.dart`).

## Crypto rules

- Every cryptographic operation lives in `CryptoRepository` — never inline crypto in cubits or
  widgets. Argon2id derivation runs in `Isolate.run` to keep the UI thread free; keep any new
  heavy crypto off the main isolate the same way.
- Secrets at rest go through `SecureStorageRepository` (flutter_secure_storage), never
  HydratedBloc/JSON state.
- Anything touching vault export/import must keep backward compatibility with existing
  `BackupFile.version` values.

## Presentation

- **"Cannot read it" and "must not show it" are different, and must never share a branch.**
  A message sealed under a key this device lacks is *locked* — render a placeholder with its
  author and time, because nothing is wrong and it opens when the key arrives. A message whose
  signature fails is *dropped*, silently and completely, because a placeholder there would let a
  forger prove a message existed. Collapsing the two is what made a channel with no key look
  empty. Same rule for any surface that decrypts: `ARCHITECTURE.md` §4, *Three things a client can
  do with a row*.
- **An unencrypted message is badged, always.** Webhooks (and later bot commands) write bodies the
  server can read, in channels where everything else is sealed. `MessageOriginBadge` says so and
  has no off switch — and the *grouping* rule has to agree, or a badge-less row tucks under a
  badged one. Group by `ChatMessage.groupKey`, never by `authorId`.
- **Keep widget files small — one widget per file wherever possible.** A component gets its own
  folder containing its main file plus one file per helper widget (e.g.
  `manage/panels/invites_panel.dart` + `invites/widgets/invite_form.dart`). Helper widgets that are
  genuinely a few lines may stay private (`_Foo`) in the same file, but a file approaching a few
  hundred lines with multiple widget classes must be split into a folder. Refactor files toward
  this shape whenever you touch them.
- **Colors:** never hard-code a `Color` in a widget. Themed values live in
  `theme/palettes/*.dart` (one `AppPalette` per file, `dark` + `light`), surfaced through a
  semantic getter on `ThemeState` (`bgSecondary`, `textTertiary`, `channelActiveBg`, ...).
  Widgets read it with `context.theme` (`theme/theme_context.dart`) — `ThemeState` is a
  `ThemeExtension` installed on every `ThemeData` — never as a constructor parameter threaded
  down from whoever built the widget. To add a color: add the field to
  `PaletteColors`, give all four palettes both modes, add one getter — no
  `isDarkTheme ? ... : ...` branching inside widgets. Status colors (success/warning/error,
  online-green) stay in `CustomColors`, are shared across palettes, and must never be
  repurposed as accents.
- **The surface ladder is the layout language, and its order is load-bearing:** `bgPrimary` is
  the *canvas* the floating panels sit on and is never a content background; `bgContent` carries
  content panels (chat, stage, settings body); `bgSecondary` carries chrome panels (sidebar,
  members); `bgTertiary` is inset (fields, composer); `bgElevated` floats above everything
  (dialogs, menus, popovers). `test/app_palette_test.dart` fails if a palette breaks the
  ordering or drops body text below WCAG AA on the content panel.
- **Type:** `AppText` (`theme/app_text.dart`) holds the scale: six sizes, 11 / 12 / 13 / 14 /
  15 / 21, and every style is one of them. A call site never sets a size —
  `copyWith(fontSize:)` is banned; a place that needs a size needs a token. Styles carry size,
  weight, spacing and family but never colour — finish one with
  `.copyWith(color: theme.textSecondary)`. Geist for UI; `figure`/`kbd`/`code`/`mnemonic` are
  mono, reserved for figures that line up or tick in place, keyboard chips and strings copied
  exactly. Timestamps (`meta`) are sans with tabular figures.
- **Radius:** three steps in `K` — `radiusRow` (8, anything pressed), `radiusCard` (12,
  cards, menus, panels and dialogs), `radiusPill`. No literal radii in widgets.
- **Selection:** one language everywhere — a flat `channelActiveBg` tint and a 1px
  `channelActiveBorder`, the same width as the resting hairline (`SelectableSurface`, `NavRow`,
  the voice card). No gradients, no glow: primary buttons and the send control are solid accent.
- **Motion:** durations are `AppMotion` tokens (`react`, `state`, `enter`), never literals.
- **Depth:** elevated chrome reads its shadow from `AppShadows`, never a hand-rolled `BoxShadow`.
- **A field's tap target is the box it looks like, not the strip of text inside it.** A bare
  `TextField` only hit-tests its own decoration, so one drawn inside a taller bar — the
  composer, a search pill with a magnifier beside it — leaves the padding, the icon and the
  gaps between controls inert, and the only way to get a caret is to aim at the placeholder.
  Wrap the painted box in `TapToFocus` (`presentation/common/tap_to_focus.dart`); buttons
  inside keep their own taps and cursors. `AppTextField` needs nothing — Material's own
  decoration is the target — but its label is wrapped, so clicking the label focuses the
  field. `test/field_hit_area_test.dart` taps the corners of each bar on every platform.
- **Motion has a vocabulary — use it, don't invent a duration.** `AppMotion` (`theme/`)
  names three lengths by job: `react` for a control answering the pointer, `state` for one
  changing under your hand, `enter` for something arriving that the user did not do. The
  rule they encode: **nothing the user is waiting on runs longer than `state`.** Two things
  moving over the same duration on different curves still read as two animations, so take
  the curve from there too (`settle`, `arrive`, `pop`, `panel`). Panel travel times stay in
  `K`, beside the geometry they move.
- **An arrival animates once, and only for what actually arrived.** Anything that animates
  on first build animates a whole backlog the moment a list is reopened — so the list primes
  (`ChatMessageList._seen`, `MessageReactionsBar._shown`) and only what turns up afterwards
  moves. Prime in `initState`, never a `late` field: a `late` initialiser runs on first
  *access*, which is the first `didUpdateWidget`, by which point `widget` already holds the
  new list and the priming swallows the arrival it exists to let through. The animating
  widget then captures the answer in its own `initState` and stops asking, or the next
  rebuild tears the animation out mid-flight.
- **Animate what changed, not what happens to be on the same widget.** An `AnimatedContainer`
  animates *every* property it is given — handed a padding that is really a layout mode, a
  window crossing the breakpoint gets the wrong density for 140ms (`NavRow` keeps its padding
  in a plain `Padding` inside). And `AnimatedDefaultTextStyle` *replaces* the ambient style
  rather than merging, unlike `Text(style:)` — merge explicitly or `AppText`'s inherited
  metrics quietly go missing.
- **An `InkWell` inside a box that paints its own background needs a `Material` inside that
  box.** Ink is drawn on the nearest `Material` *above* the well, so a highlight under an
  opaque fill is painted and then covered — the button works, nothing lights up, and the tap
  target is invisible until you click it. `PopoverSurface` puts its `Material` inside its
  fill for this reason, and `ComposerIconButton` carries one. A control whose *child* is
  opaque (a gradient, an avatar) can't be fixed this way at all and must lift itself —
  see `ComposerSendButton`. `test/hover_feedback_test.dart` renders the pixels with the
  pointer on and off, because this is a bug you cannot see by reading the widget tree.
- **Shared UI to reuse before hand-rolling:** `AppPanel` (a floating panel), `CanvasBackdrop`
  (the lit ground), `NavRow` (any navigable sidebar row), `SquircleAvatar` / `UserAvatar`,
  `SpeakingRing`, `StatusChip`, `ContextMenuPanel` + `ContextMenuItem`, `TapToFocus`. Avatar gradients come
  from `IdentityGradients` and are deliberately *not* palette-derived, so a person looks the
  same to everyone in a channel whatever theme each is running.
- Layout constants (widths, heights, paddings, radii reused across files) go in `K`
  (`data/constants.dart`), not magic numbers.
- Dialogs use `showCustomDialog` / `AppModal` from `presentation/common/`; pass existing cubits
  in with `MultiBlocProvider` + `BlocProvider.value` (never construct a new cubit for a dialog).
- Toasts/errors go through `HelperMethods.showToast` / `showError` (toastification) — no
  SnackBars. Debug logging through `HelperMethods.printDebug`, not bare `print` (Dart side).
- `buildWhen` / `listenWhen` are used on hot-path builders to limit rebuilds (see
  `home_screen.dart`); do the same for anything rebuilding inside the call screen.
- Platform gating: `kIsWeb` for web, `Platform.isX` for desktop specifics. The Rust bridge is
  desktop/mobile only (`if (!kIsWeb) await RustLib.init()`); web must degrade gracefully.
- Navigation is go_router via `AppRoutes`; use `HelperMethods.pushOrGoToRoute` when a route must
  behave differently on web.

## Style

- Section banners use box-drawing comments, matching existing files:
  `// ── Section name ──────────────────────────`
- `///` doc comments on public members explain *why* / non-obvious constraints, not what the
  code visibly does.
- Files snake_case; classes UpperCamelCase; private mixins/widgets `_`-prefixed.
- Relative imports inside `lib/` (`../../../data/...`), ordered: `dart:` → `package:flutter` →
  other packages → relative. No `package:rift/...` self-imports.
- Lints: `flutter_lints` defaults (`analysis_options.yaml`). `flutter analyze` must be clean
  before committing.

## Rust side (`rust/`)

- `rust/src/api/` is *only* the bridge: each function Dart can call exists there exactly once,
  on every platform, and dispatches into `rust/src/screenshare/`. The codegen scans `api/`, so
  nothing internal may be `pub` there — internals are `pub(crate)` and live outside it.
- `cfg(desktop)` (emitted by `rust/build.rs` for Windows/Linux/macOS) gates everything that
  touches LiveKit; per-OS code sits in its own file (`audio/linux.rs`, `audio/windows.rs`,
  `thumbnail.rs`) gated at the `mod` line, not item by item.
- Functions crossing the bridge return `Result<T, String>` — errors are plain strings for Dart.
- Log with `log::` (`info!`/`warn!`), never `println!`: `init_app` installs a logger on every
  platform and stdout goes nowhere in a Windows release build.
- Pure logic (frame sizing, pixel sampling, sample conversion) is a plain function with unit
  tests; `cargo test` runs them anywhere. `cargo test live_ -- --ignored` runs a real share
  against a LiveKit server (see `rust/src/screenshare/live_test.rs`).
- `rust/src/frb_generated.rs` and `lib/src/rust/` are generated. After changing the API surface,
  regenerate with flutter_rust_bridge codegen (config in `flutter_rust_bridge.yaml`,
  pinned to flutter_rust_bridge 2.13.0 — keep the Dart package and codegen versions in lockstep).
- Local native builds: `./build_rust_local.sh` / `build_rust_local.bat`. CI precompiles binaries
  via cargokit on pushes to `production`.

## Backend

- DB changes: add a new numbered file in `server_migrations/` (never edit an applied migration)
  and update the migration's own prose — it is the reference now.
- Edge Function changes: keep the `{success, data, error}` 200-always envelope, enforce
  permissions server-side (`is_server_admin` / `is_channel_manager` / `can_create_tokens`,
  delegation rule: you can only grant what you hold), and update `API.md` in
  `rift-self-host`.

## Git

- Commit locally early and often — one logical change per commit (a cubit refactor, a widget,
  a migration), not end-of-session mega-commits. Imperative subject line ("Add channel presence
  rows to sidebar"), body only when the why isn't obvious.
- `flutter analyze` must pass before every commit.
- Never commit generated-file changes (`*.g.dart`, `lib/src/rust/`, `frb_generated.rs`) separately
  from the source change that produced them.

## Commands

```
dart run build_runner build          # regen .g.dart after @JsonSerializable changes
flutter analyze                      # must be clean
flutter run -d <device>              # run
dart run inno_bundle:build --release # Windows installer
flutter build linux --release        # Linux build
```

## Testing

A `test/` suite covers **pure, deterministic logic**:
- **Auth crypto** (`crypto_repository_test.dart`) — server-identity derivation
  (determinism, per-`(host, serverId)` separation), SIWS message signing, encoding.
- **E2E messaging crypto** (`chat_crypto_test.dart`) — chat-identity derivation and
  its domain separation from the auth key, DM-key symmetry, channel-key wrap/unwrap,
  attachment-blob `encryptBytes`/`decryptBytes`, and the signed message envelope, each
  with its negative case (forge, replay across channels, key-version tamper, wrong key).
- **Models / state** (`server_model_test.dart`, `notifications_state_test.dart`,
  `message_model_test.dart`, `message_body_test.dart`, `message_reaction_test.dart`,
  `public_server_test.dart`) — JSON round-trips, token-freshness and unread math, the
  `signedPayload` binding, permission defaults, the structured message body (attachment
  round-trip + legacy plain-text compatibility), reaction parsing + `ChatMessage.copyWith`,
  and the directory row plus the tag rules it mirrors from central migration 007.
- **Storage isolation** (`storage_namespace_test.dart`) — `RIFT_PROFILE` namespacing.

One deliberate exception to the "no widget tests" rule below:
`chat_composer_alignment_test.dart` pins the composer's layout invariants (every
control on one centre line, the bar's height unchanged by emoji input, multi-line
growth). It exists because that alignment regressed twice; it pumps only the
composer with an in-memory `HydratedBloc` storage, so it stays pure and fast.

Run with `flutter test`; it must pass (alongside `flutter analyze`) before committing.

Keep tests pure and fast: no network, Supabase, platform channels, or a running app.
Good targets are repository *pure functions* (crypto, encoding), cubit `State` classes
(unread math, `copyWith` invariants), and model `fromJson`/`toJson`. Don't add widget or
integration tests, and don't mock the backend, unless asked — backend behaviour is
verified against the local stack (see `LOCAL_DEV.md`), not with mocks. When you fix a
logic bug in one of these pure areas, add a case that would have caught it.

**The databases have their own suites, and they are not in this repository.**
RLS is security and Dart cannot see it, so each schema tests itself where it
lives: `./scripts/db_test.sh` in `rift-self-host` for a server, and the same
path in `rift-central` for the shared tier. Each test impersonates a user by
setting `request.jwt.claims` and `SET LOCAL ROLE authenticated`, so it exercises
the same path PostgREST takes, and runs in one transaction ending in `ROLLBACK`.
Run the relevant one after touching a migration, and add a case whenever you add
a policy, a grant or a `SECURITY DEFINER` function.

**Live behaviour is recorded in `MANUAL_TESTING.md`.** Realtime delivery, cross-device
key distribution, presence, LiveKit, the Android foreground service and per-width
layout cannot be covered by either suite, so what has actually been driven through the
real UI — and what has *not* — is logged there, along with how to drive the Linux and
Android clients (`GDK_BACKEND=x11` + `xdotool`, and `adb`). Read it before assuming
something is untested, and add to it whenever you verify something live.
