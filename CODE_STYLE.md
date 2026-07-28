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
  before the implementation, and the cubit class or another mixin supplies it.
- Prefer calling a **public** member across mixins. A *private* member implemented in one
  mixin and called from another trips `unused_element` — either keep both the call and the
  implementation in the same mixin, or make the member public.
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

## 8. Before you commit

1. `flutter analyze` clean (no new infos either).
2. `flutter test` green; add pure tests for any pure logic you extracted or fixed.
3. `dart format` on what you touched.
4. Did the file you edited get *closer* to the shapes above, or further away?
5. Update `AGENTS.md` / `schema.md` / `edge_functions.md` if you changed a convention,
   a table, or an endpoint.
