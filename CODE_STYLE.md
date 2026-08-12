# CODE_STYLE.md — how Rift code is organised

`AGENTS.md` says *what* the conventions are (Bloc, `ThemeState` colours, `APIResponse`,
migrations). This file says *how big things may get and when to split them*, because that
is what actually decays over time. Both are binding for humans and agents.

The rule behind every rule below: **a file should have one job, and you should be able to
guess its contents from its name.**

## 1. Size budgets

| Kind of file | Comfortable | Split before |
| --- | --- | --- |
| Widget | < 150 lines | 200 |
| Cubit part / mixin | < 200 lines | 250 |
| Cubit hub (`*_cubit.dart`) | < 300 lines | 400 |
| Repository | < 250 lines | 350 |
| Pure model / helper | < 150 lines | 200 |

These are guides, not lint rules — a 210-line widget that is genuinely one thing is fine.
A 180-line file holding three unrelated things is not. **Refactor toward these shapes
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

- **Colours**: `ThemeState` getters, or `CustomColors` for semantic status. Never a
  `Color(0x…)` in a widget.
- **Layout numbers reused across files**: `K` in `data/constants.dart`, under a banner
  section (e.g. `K.composerControlSize`). A number used in exactly one file may stay a
  `static const` at the top of that file — named, not inline.
- **Tuning numbers that must agree** (a control's size and the field floored to it) belong
  in *one* constant that both read. If two literals must match, they must be one constant.
- **Strings shown to users** stay at their use site; **protocol strings** (scopes, error
  codes, storage prefixes) get a constant.

## 5. Cubits: split by seam, not by size

Large cubits become `part` files with private mixins (`AGENTS.md` §State management). The
seams that have worked for chat, in order:

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

## 7. Comments that earn their place

- `///` on every public class/member: what it is for and any non-obvious constraint.
- Inline `//` only for *why*, especially where the obvious code would be wrong (why the
  strut is pinned, why a pending bubble survives a merge).
- Section banners inside longer files: `// ── Section ─────────────`.
- Delete stale comments as you edit — a wrong comment is worse than none.

## 8. Shared UI: use the kit

Before hand-rolling chrome, check `presentation/common/`:

| Need | Use |
| --- | --- |
| A dialog | `AppModal` + `showAppModal` (`showCustomDialog` for a bare one) |
| A dialog opened from a context menu | `showDialogFromMenu` — never `showCustomDialog` with the menu's context, see its doc |
| Two groups in one dialog | `ModalColumns` — side by side when there's room, stacked when there isn't |
| "Are you sure?" | `showConfirmDialog` — returns a non-null `bool`; dismiss means no |
| An inline error / notice | `MessageBanner` |
| A button | `AppButton` (`AppButtonVariant.danger` for destructive) |
| A settings heading / toggle | `SectionTitle`, `SettingToggleRow` |
| An onboarding-style hero | `FeatureHeader` |
| A prose field with a length limit | `AppTextField(maxLines:, maxLength:)` — the counter is already themed |
| A pick-one row of chips | `SelectableSurface` (see `ChipSelector`, `TagFilterBar`) — it sets its own colours, so pass size and weight only |

A dialog that doesn't fit `AppModal` (its body scrolls internally, e.g. a
`ListView`) should say so in a comment rather than silently re-implementing the
chrome.

## 9. Before you commit

1. `flutter analyze` clean — the tree is at **zero issues**, including infos, so
   any output is yours.
2. `flutter test` green; add pure tests for any pure logic you extracted or fixed.
3. `dart format` on what you touched.
4. Did the file you edited get *closer* to the shapes above, or further away?
5. Update `AGENTS.md` / `schema.md` / `edge_functions.md` if you changed a convention,
   a table, or an endpoint.
