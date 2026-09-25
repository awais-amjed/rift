import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../../data/classes/livekit_node.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// One LiveKit node in the server settings list.
///
/// **The name is editable, including the default's — especially the
/// default's.** The label is what a channel manager picks from and what a
/// member is shown, so it should be a place; and the one node every server is
/// guaranteed to have is created called "Default", which is the one name that
/// is never a place. It is also the node most likely to need renaming, being
/// whatever box the server already runs on.
///
/// The default shows no *remove* control, because it cannot be removed — it
/// is the server's own LiveKit URL under a label, and the field above this
/// list is where its address is changed. Offering a button the server refuses
/// would be worse than not offering one. That left the default row with no
/// controls at all until renaming arrived.
///
/// It is marked as the default in words, but only when its label does not
/// already say so: an unrenamed one is called "Default", and
/// "Default (default)" is what that produced.
class VoiceRegionRow extends StatefulWidget {
  final LiveKitNode node;
  final bool enabled;
  final VoidCallback onRemove;

  /// Called with the new label, already trimmed and known to differ from the
  /// current one. Not called for an empty name — a region with no name is a
  /// row nobody can choose from a dropdown.
  final ValueChanged<String> onRename;

  const VoiceRegionRow({
    super.key,
    required this.node,
    required this.enabled,
    required this.onRemove,
    required this.onRename,
  });

  @override
  State<VoiceRegionRow> createState() => _VoiceRegionRowState();
}

class _VoiceRegionRowState extends State<VoiceRegionRow> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  /// Guards the commit, because leaving the field can happen twice — once
  /// from the keyboard and again from the focus change it causes.
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The label, plus "(default)" when that is not what it already says.
  String get _title {
    final label = widget.node.label;
    if (!widget.node.isDefault) return label;
    if (label.trim().toLowerCase() == 'default') return label;
    return '$label (default)';
  }

  void _startEditing() {
    if (!widget.enabled) return;
    setState(() {
      _editing = true;
      _controller.text = widget.node.label;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
    _focus.requestFocus();
  }

  void _cancel() {
    // Clearing `_editing` is itself the guard: removing the field drops
    // focus, and the listener only commits while still editing — so the edit
    // being abandoned cannot be saved on the way out.
    setState(() => _editing = false);
  }

  void _commit() {
    if (_committing) return;
    _committing = true;
    final name = _controller.text.trim();
    setState(() => _editing = false);
    if (name.isNotEmpty && name != widget.node.label) {
      widget.onRename(name);
    }
    _committing = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_editing) _field(theme) else _name(theme),
                const SizedBox(height: 2),
                Text(
                  widget.node.url,
                  style: AppText.secondary.copyWith(color: theme.textQuaternary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!_editing) ...[
            IconButton(
              onPressed: widget.enabled ? _startEditing : null,
              mouseCursor: WidgetStateMouseCursor.clickable,
              icon: const Icon(Icons.edit_outlined, size: 16),
              tooltip: 'Rename region',
              color: theme.textTertiary,
            ),
            if (!widget.node.isDefault)
              IconButton(
                onPressed: widget.enabled ? widget.onRemove : null,
                mouseCursor: WidgetStateMouseCursor.clickable,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove region',
                color: theme.textTertiary,
              ),
          ],
        ],
      ),
    );
  }

  /// The name as a target, not a strip of text: the whole width answers the
  /// pointer, so renaming does not depend on hitting the word itself.
  Widget _name(ThemeState theme) => MouseRegion(
    cursor: widget.enabled
        ? SystemMouseCursors.click
        : SystemMouseCursors.basic,
    child: GestureDetector(
      onTap: _startEditing,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        child: Text(
          _title,
          style: AppText.body.copyWith(color: theme.textPrimary),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );

  /// Escape abandons the edit. Wired here rather than left to the field,
  /// because a bare [TextField] does nothing with it and the comment below
  /// would otherwise be describing a key that goes nowhere.
  Widget _field(ThemeState theme) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): _cancel,
    },
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      style: AppText.body.copyWith(color: theme.textPrimary),
      cursorColor: theme.textPrimary,
      // Enter commits, Escape abandons — the two answers a one-field edit has.
      onSubmitted: (_) => _commit(),
      inputFormatters: [LengthLimitingTextInputFormatter(40)],
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        hintText: 'Region name',
        hintStyle: AppText.body.copyWith(color: theme.textQuaternary),
      ),
    ),
  );
}
