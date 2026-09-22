# CODE_STYLE.md — how Rift code is organised

`AGENTS.md` says *what* the conventions are (Bloc, `ThemeState` colours, `APIResponse`,
migrations). This file says *how big things may get and when to split them*, because that
is what actually decays over time. Both are binding for humans and agents.

The rule behind every rule below: **a file should have one job, and you should be able to
guess its contents from its name.**

## 1. Size budgets

| Kind of file | Comfortable | Look again at |
| --- | --- | --- |
| Widget | < 150 lines | 200 |
| Cubit part / mixin | < 200 lines | 250 |
| Cubit hub (`*_cubit.dart`) | < 300 lines | 400 |
| Repository | < 250 lines | 350 |
| Pure model / helper | < 150 lines | 200 |

These are guides, not lint rules. **The split trigger is a second responsibility you can
name, not a line count.** A composer or a message row that genuinely needs everything in
one place can run to 400 or 500 lines and stay; a 180-line file holding three unrelated
things is the problem. When a file is over its budget and is one job, say so in a line at
the top of its doc comment so the next reader does not re-ask — worded "Over the
<kind> budget and one job: …", which `scripts/style_check.sh` looks for and marks
`(noted)`.

`scripts/style_check.sh` lists what is over budget. It is a report for the reviewer, not
a gate: the question at each line is "is this one job?". **Refactor toward these shapes
whenever you touch a file**, not in a separate "cleanup" pass that never comes.

## 2. One widget per file

- A component with helpers gets a **folder**: `composer/chat_composer.dart` plus
  `composer_icon_button.dart`, `composer_text_field.dart`, … — one widget each.
- A private helper widget may share the file only if it is genuinely a few lines and used
  only there. Two public widget classes in one file is always a split.
- Name the file after the widget (`message_hover_toolbar.dart` → `MessageHoverToolbar`).
- Extracting a widget also means giving it a `///` comment saying what it is for; if you
  can't write that sentence, the seam is wrong.

Reference shape (`lib/presentation/common/chat/`):

```
chat/
  chat_message_list.dart      date_divider.dart      typing_indicator.dart
  composer/                   attachments/           message_row/          reactions/
```

## 3. Don't repeat — extract, don't copy

- **Second copy is a warning, third is a bug.** When the same transform shows up in two
  cubits, pull it out *before* adding the third caller.
- Extract to a **pure function or class with no state and no I/O**
  (`logic/services/chat_message_ops.dart`, `logic/services/mime_util.dart`). Pure code is
  reusable, testable without a running app, and can't leak state between callers.
- **The extraction is only half the job — write the tests.** The point of pulling
  `VideoStatsSampler` or `ParticipantVideo` out of a widget is that their edge cases
  (a repeated timestamp, a muted camera vs a muted screenshare) become reachable.
  A pure helper with no test file has bought you nothing but an extra import.
- Prefer to put a transform **on the state class it transforms** when one exists
  (`NotificationsState.incremented`) — that keeps the invariant next to the readers
  that assume it, rather than in a cubit that happens to call it.
- Widgets that differ only by data take parameters; they don't get forked.
- If two things look similar but drift for real reasons (channel vs DM transports), share
  the *logic* and keep the *transport* separate — that is exactly what
  `ChatMessageOps` + per-cubit send mixins do.

## 4. Central variables — no loose literals

- **Colours**: `context.theme` getters, `CustomColors` for semantic status, or
  `MediaColors` for anything drawn over video, photos or the scrim. Never a
  `Color(0x…)` outside `presentation/theme/`, and never `ThemeState` as a constructor
  parameter.
- **Type sizes**: an `AppText` token, never `copyWith(fontSize:)`. **Radii**: `K.radiusRow` /
  `radiusCard` / `radiusPill`, never a literal.
- **Layout numbers reused across files**: `K` in `data/constants.dart`, under a banner
  section (e.g. `K.composerControlSize`). A number used in exactly one file may stay a
  `static const` at the top of that file — named, not inline.
- **Tuning numbers that must agree** (a control's size and the field floored to it) belong
  in *one* constant that both read. If two literals must match, they must be one constant.
- **Strings shown to users** stay at their use site; **protocol strings** (scopes, error
  codes, storage prefixes) get a constant.

## 5. Cubits: split by seam, not by size

Large cubits become `part` files with private mixins (`AGENTS.md` §State management). The
general rule: split by a responsibility the reader can name from the file name, never by
"this file got long". For chat the seams that have worked, in order, are:

1. `*_conversations.dart` — the list of things you can open.
2. `*_history.dart` — opening one, paging it, decrypting rows.
3. `*_send.dart` — composing and posting, plus attachment upload/fetch.
4. `*_reactions.dart` — reactions.

Cross-mixin contracts:

- A mixin declares what it needs as an **abstract getter/method** at the top, grouped
  before the implementation, and something else supplies it.
- **Satisfy those declarations from the cubit class**, not from a sibling mixin. A
  *private* member declared abstract in one mixin and implemented in another trips
  `unused_element` — the analyzer resolves the call to the abstract declaration and never
  sees the implementation. The class is the meeting point: it holds the state and the
  handful of internals several mixins share (`_uploadBackup`, `_postAuthSync`).
- If a member really must live in a sibling mixin, make it **public** — `unused_element`
  only fires on private declarations. Say in its doc comment that it is cubit-internal
  (`setupRoomListeners`).
- The class calling *into* a mixin needs no declaration at all — that's plain inheritance.
- State stays in the cubit class (`final Map<String, Uint8List> _dmKeys = {}`) with
  `@override` on the field and an abstract getter in each mixin that reads it.

## 6. Widgets are UI-only

No `dart:io`, no platform plugins, no HTTP inside a widget. Recording, file system, and
network work belong in `logic/services/` or `data/repositories/`, and the widget holds
only what it needs to *render* (`VoiceNoteRecorder` is the model to copy). This keeps
widgets testable and lets a service be reused by a second surface later.

## 7. Rebuilds and lists

- `const` constructors and `const` children wherever the compiler lets you; a widget whose
  fields are all final and has no `const` constructor is a bug.
- Any list that can grow is `ListView.builder` / `.separated` (or a sliver), never a plain
  `ListView(children:)` or a `Column` in a `SingleChildScrollView`. Items get a `key` when
  they can reorder or be removed.
- Read the narrowest slice of state a widget needs: `context.select`, or `BlocBuilder` with
  `buildWhen`. Watching a whole state at the top of a screen rebuilds every row on every
  typing indicator. `home_screen.dart` shows the pattern.
- Nothing heavy in `build`: no decoding, sorting, filtering or JSON parsing. Do it once
  where the data changes (the cubit, or the state class) and hand the widget the result.
- Anything expensive per frame (image decode, crypto, classification) runs off the main
  isolate — see `ImageSafetyWorker` and `CryptoRepository`.

## 8. Async lifecycle

- Every `StreamSubscription`, `Timer` and controller a cubit or `State` owns is cancelled or
  disposed in `close()` / `dispose()`. The `cancel_subscriptions` and `close_sinks` lints
  catch the obvious cases; the rest is on you.
- After an `await` in a widget, check `mounted` before touching `context` or calling
  `setState`. In a cubit, check `isClosed` before `emit`.
- A future you deliberately drop is wrapped in `unawaited(...)`; the `unawaited_futures`
  lint refuses a bare one. If you cannot say why it is safe to drop, await it.
- Errors reach the user through `HelperMethods.showError` and debug output through
  `HelperMethods.printDebug` (Dart) / `log::` (Rust) — never `print` or `println!`.

## 9. Comments that earn their place

- `///` on every public class/member: what it is for and any non-obvious constraint.
- Inline `//` only for *why*, especially where the obvious code would be wrong (why the
  strut is pinned, why a pending bubble survives a merge).
- Section banners inside longer files: `// ── Section ─────────────`.
- Delete stale comments as you edit — a wrong comment is worse than none.

## 10. Shared UI: use the kit

Before hand-rolling chrome, check `presentation/common/`:

| Need | Use |
| --- | --- |
| A dialog | `AppModal` + `showAppModal` (`showCustomDialog` for a bare one); a list that scrolls itself goes in `body:`, a form in `content:` |
| A dialog opened from a context menu | `showDialogFromMenu` — never `showCustomDialog` with the menu's context, see its doc |
| Two groups in one dialog | `ModalColumns` — side by side when there's room, stacked when there isn't |
| "Are you sure?" | `showConfirmDialog` — returns a non-null `bool`; dismiss means no |
| An inline error / notice | `MessageBanner` — every error, never a bare red `Text`; `caution` is the amber kind |
| A button | `AppButton` (`AppButtonVariant.danger` for destructive) |
| The buttons at the end of a panel or dialog | `ButtonFooter` — equal widths at the trailing edge, never one stretched |
| A two- or three-way choice that shapes a form | `SegmentedControl` (sign in / create, person / bot, text / voice) |
| A word in a pill (role, Bot, Banned) | `LabelPill` |
| Waiting on something | `LoadingDots`, never `CircularProgressIndicator` |
| Nothing here yet, connecting, failed | `EmptyState` (`busy:` for the dots, `detail:` for a raw cause) |
| A settings heading / toggle | `SectionTitle`, `SettingToggleRow` |
| An onboarding-style hero | `FeatureHeader` |
| A prose field with a length limit | `AppTextField(maxLines:, maxLength:)` — the counter is already themed |
| A pick-one row of chips | `SelectableSurface` (see `ChipSelector`, `TagFilterBar`) — it sets its own colours, so pass size and weight only |

Nothing hand-rolls dialog chrome: a body that scrolls internally goes in
`AppModal(body:)`, which is what the slot is for.

## 11. Before you commit

1. `flutter analyze` clean — the tree is at **zero issues**, including infos, so
   any output is yours. Vendored (`rust_builder/`) and untracked (`tool/`) code is
   excluded in `analysis_options.yaml`.
2. `flutter test` green; add pure tests for any pure logic you extracted or fixed.
3. `dart format` on what you touched.
4. `scripts/style_check.sh` — anything new on that report is yours to justify or fix.
5. Did the file you edited get *closer* to the shapes above, or further away?
6. Update `AGENTS.md` if you changed a convention,
   a table, or an endpoint.
