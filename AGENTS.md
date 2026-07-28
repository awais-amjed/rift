# AGENTS.md — Rift coding conventions

Rift is a self-hostable Discord alternative: Flutter (UI, all platforms) + Rust (screen capture
pipeline via flutter_rust_bridge) + Supabase (self-hostable backend: Postgres, Edge Functions,
Storage) + LiveKit (voice/video). Design goals: clean minimal UI, maximum use of space (every
piece of chrome can collapse/hide), fast native screensharing.

These conventions are extracted from the existing code. Match them; don't introduce parallel
patterns. For how identity, auth, and encryption work (current and planned), see
`ARCHITECTURE.md` — consult it before touching vault, auth, backup, or (future) messaging code.
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
    theme/        # app_theme.dart (ThemeData) + custom_colors.dart (all color values)
  src/rust/       # GENERATED flutter_rust_bridge bindings — never edit by hand
rust/src/api/     # Rust API surface exposed to Flutter
server_migrations/  # Numbered SQL migrations (001_..., 002_...)
schema.md           # DB schema doc — update when tables/buckets change
edge_functions.md   # Edge Function API doc — update when functions change
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

- **Keep widget files small — one widget per file wherever possible.** A component gets its own
  folder containing its main file plus one file per helper widget (e.g.
  `invite_modal/invite_modal.dart` + `invite_modal/permission_row.dart`). Helper widgets that are
  genuinely a few lines may stay private (`_Foo`) in the same file, but a file approaching a few
  hundred lines with multiple widget classes must be split into a folder. Refactor files toward
  this shape whenever you touch them.
- **Colors:** never hard-code a `Color` in a widget. Every value lives in `CustomColors`
  (paired `...Dark` / `...Light` constants), surfaced through a semantic getter on `ThemeState`
  (`bgSecondary`, `textTertiary`, `channelActiveBg`, ...). Widgets read them via
  `BlocBuilder<ThemeCubit, ThemeState>`. To add a color: add both Dark/Light constants + one
  getter — no `isDarkTheme ? ... : ...` branching inside widgets.
- Planned direction: user-selectable **accent palettes** (indigo stays the default). Keep all new
  color usage semantic (via `ThemeState` getters) so the accent can be swapped per-user without
  touching widgets. Semantic status colors (success/warning/error, speaking-green, muted-rose)
  are shared across palettes and must not be repurposed as accents.
- Layout constants (widths, heights, paddings reused across files) go in `K`
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

- Public API surface for Flutter lives in `rust/src/api/`; platform-specific code is split per
  file (`audio_windows.rs`, `audio_linux.rs`) with `#[cfg]` guards.
- Functions crossing the bridge return `Result<T, String>` — errors are plain strings for Dart.
- `rust/src/frb_generated.rs` and `lib/src/rust/` are generated. After changing the API surface,
  regenerate with flutter_rust_bridge codegen (config in `flutter_rust_bridge.yaml`,
  pinned to flutter_rust_bridge 2.11.1 — keep the Dart package and codegen versions in lockstep).
- Local native builds: `./build_rust_local.sh` / `build_rust_local.bat`. CI precompiles binaries
  via cargokit on pushes to `production`.

## Backend

- DB changes: add a new numbered file in `server_migrations/` (never edit an applied migration)
  and update `schema.md`.
- Edge Function changes: keep the `{success, data, error}` 200-always envelope, enforce
  permissions server-side (`is_server_admin` / `is_channel_manager` / `can_create_tokens`,
  delegation rule: you can only grant what you hold), and update `edge_functions.md`.

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
  `message_model_test.dart`, `message_body_test.dart`, `message_reaction_test.dart`) — JSON
  round-trips, token-freshness and unread math, the `signedPayload` binding, permission
  defaults, the structured message body (attachment round-trip + legacy plain-text
  compatibility), and reaction parsing + `ChatMessage.copyWith`.
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
