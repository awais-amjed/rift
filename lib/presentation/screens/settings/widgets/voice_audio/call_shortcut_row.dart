import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/call_shortcuts.dart';
import '../../../../../data/classes/key_shortcut.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/shortcuts/call_shortcut_listener.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One call shortcut: its keys, and the buttons to pick or clear them.
///
/// Picking listens for the next key pressed with whatever modifiers are held.
/// Esc on its own cancels, and so does clicking anywhere else, which takes
/// the focus the listening needs.
class CallShortcutRow extends StatefulWidget {
  final CallShortcut action;
  final KeyShortcut? keys;

  const CallShortcutRow({super.key, required this.action, required this.keys});

  @override
  State<CallShortcutRow> createState() => _CallShortcutRowState();
}

class _CallShortcutRowState extends State<CallShortcutRow> {
  final FocusNode _focus = FocusNode();
  bool _capturing = false;

  /// The last press could not be a shortcut: a plain key, which is typing.
  bool _refused = false;

  @override
  void dispose() {
    if (_capturing) CallShortcutListener.capturing = false;
    _focus.dispose();
    super.dispose();
  }

  void _setCapturing(bool on) {
    if (!mounted || on == _capturing) return;
    CallShortcutListener.capturing = on;
    setState(() {
      _capturing = on;
      _refused = false;
    });
    if (on) {
      _focus.requestFocus();
    } else {
      _focus.unfocus();
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!_capturing) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    // Not a key the user pressed: see PushToTalkSection's capture.
    if (event.synthesized) return KeyEventResult.ignored;

    final keys = KeyShortcut.fromPress(
      event.logicalKey,
      HardwareKeyboard.instance,
    );
    if (keys == null) return KeyEventResult.handled;
    if (keys == KeyShortcut(keyId: LogicalKeyboardKey.escape.keyId)) {
      _setCapturing(false);
      return KeyEventResult.handled;
    }
    if (!keys.isUsable) {
      setState(() => _refused = true);
      return KeyEventResult.handled;
    }
    context.read<AppCubit>().setCallShortcut(widget.action, keys);
    _setCapturing(false);
    return KeyEventResult.handled;
  }

  String get _title => switch (widget.action) {
    CallShortcut.mute => 'Mute',
    CallShortcut.deafen => 'Deafen',
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final hint = AppText.secondary.copyWith(color: theme.textTertiary);
    final keys = widget.keys;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      onFocusChange: (focused) {
        if (!focused) _setCapturing(false);
      },
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: AppText.row.copyWith(color: theme.textPrimary),
                ),
                const SizedBox(height: 3),
                if (_capturing)
                  Text(
                    _refused
                        ? 'Add Ctrl or Alt, or use a function key.'
                        : 'Press the keys together, like Ctrl+Shift+M.',
                    style: hint,
                  )
                else if (keys != null)
                  Text(
                    keys.label,
                    style: AppText.kbd.copyWith(color: theme.textSecondary),
                  )
                else
                  Text('Not set', style: hint),
              ],
            ),
          ),
          if (keys != null && !_capturing)
            AppButton(
              label: 'Clear',
              variant: AppButtonVariant.secondary,
              onPressed: () =>
                  context.read<AppCubit>().setCallShortcut(widget.action, null),
            ),
          AppButton(
            label: _capturing ? 'Cancel' : 'Set keys',
            variant: _capturing
                ? AppButtonVariant.secondary
                : AppButtonVariant.primary,
            onPressed: () => _setCapturing(!_capturing),
          ),
        ],
      ),
    );
  }
}
