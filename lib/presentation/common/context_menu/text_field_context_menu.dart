import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../logic/services/host_platform.dart';
import '../../theme/app_text.dart';
import '../../theme/theme_context.dart';
import 'context_menu_item.dart';
import 'context_menu_layout.dart';
import 'context_menu_panel.dart';

/// A text field's right-click menu, drawn like every other menu in the app:
/// Cut, Copy, Paste and Select all — always all four where text can be typed,
/// greyed where they do not apply; Copy and Select all where it cannot.
///
/// Flutter's own menu lists only what applies at that moment, so an empty
/// field with no text on the clipboard had nothing to list and the
/// right-click did nothing at all. Every `TextField` passes
/// [TextFieldContextMenu.builder] or [TextFieldContextMenu.pasting];
/// `test/text_field_menu_test.dart` fails on one that forgets. A phone keeps
/// the toolbar its long press expects, and the web the browser's own menu.
class TextFieldContextMenu extends StatelessWidget {
  final EditableTextState field;

  /// First refusal on Paste, as on Ctrl+V: the composer attaches a copied
  /// picture or copied files and answers true. False leaves the paste to the
  /// field, as text.
  final Future<bool> Function()? takeClipboard;

  const TextFieldContextMenu({
    super.key,
    required this.field,
    this.takeClipboard,
  });

  /// For `TextField.contextMenuBuilder`.
  static Widget builder(BuildContext context, EditableTextState field) =>
      HostPlatform.isDesktop
      ? TextFieldContextMenu(field: field)
      : AdaptiveTextSelectionToolbar.editableText(editableTextState: field);

  /// [builder] for a field whose Paste can take more than text.
  static EditableTextContextMenuBuilder pasting(
    Future<bool> Function() takeClipboard,
  ) =>
      (context, field) => HostPlatform.isDesktop
      ? TextFieldContextMenu(field: field, takeClipboard: takeClipboard)
      : AdaptiveTextSelectionToolbar.editableText(editableTextState: field);

  void _run(VoidCallback action) {
    action();
    field.hideToolbar();
  }

  Future<void> _paste() async {
    field.hideToolbar();
    if (await takeClipboard?.call() ?? false) return;
    if (field.mounted) await field.pasteText(SelectionChangedCause.toolbar);
  }

  @override
  Widget build(BuildContext context) {
    final value = field.textEditingValue;
    final selection = value.selection;
    final editable = !field.widget.readOnly;
    // A password is never put on the clipboard from here.
    final copyable =
        !field.widget.obscureText &&
        selection.isValid &&
        !selection.isCollapsed;
    final allSelected =
        selection.isValid &&
        selection.start == 0 &&
        selection.end == value.text.length;
    const cause = SelectionChangedCause.toolbar;

    return CustomSingleChildLayout(
      delegate: ContextMenuLayout.atPoint(
        field.contextMenuAnchors.primaryAnchor,
      ),
      child: ContextMenuPanel(
        maxWidth: 200,
        children: [
          // Text that cannot be typed into — a handle, a secret to copy —
          // has nothing to cut or paste, and greying them there says
          // otherwise.
          if (editable)
            ContextMenuItem(
              icon: Icons.content_cut_rounded,
              label: 'Cut',
              trailing: const _Shortcut('X'),
              onTap: copyable
                  ? () => _run(() => field.cutSelection(cause))
                  : null,
            ),
          ContextMenuItem(
            icon: Icons.content_copy_rounded,
            label: 'Copy',
            trailing: const _Shortcut('C'),
            onTap: copyable
                ? () => _run(() => field.copySelection(cause))
                : null,
          ),
          // Never greyed: whether the clipboard holds something pasteable is
          // known only by reading it, and a picture or a file is not text.
          if (editable)
            ContextMenuItem(
              icon: Icons.content_paste_rounded,
              label: 'Paste',
              trailing: const _Shortcut('V'),
              onTap: () => unawaited(_paste()),
            ),
          ContextMenuItem(
            icon: Icons.select_all_rounded,
            label: 'Select all',
            trailing: const _Shortcut('A'),
            onTap: value.text.isNotEmpty && !allSelected
                ? () => _run(() => field.selectAll(cause))
                : null,
          ),
        ],
      ),
    );
  }
}

/// The key that does the same thing, quiet beside the label.
class _Shortcut extends StatelessWidget {
  final String letter;

  const _Shortcut(this.letter);

  @override
  Widget build(BuildContext context) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return Text(
      mac ? '⌘$letter' : 'Ctrl+$letter',
      style: AppText.kbd.copyWith(color: context.theme.textQuaternary),
    );
  }
}
