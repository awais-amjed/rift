import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/call_shortcuts.dart';
import '../../../../../data/classes/key_shortcut.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/ptt/desktop_shortcut_settings.dart';
import '../../../../../logic/ptt/xdg_trigger.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../logic/shortcuts/call_shortcut_actions.dart';
import '../../../../../logic/shortcuts/call_shortcut_listener.dart';
import '../../../../../logic/shortcuts/hook_key_state.dart';
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

  /// The key as the Linux desktop describes it, when the desktop holds it: it
  /// keeps the one it granted whatever Rift picks, so the key changes on the
  /// desktop's own page, as push-to-talk's does.
  final String? desktopKey;

  const CallShortcutRow({
    super.key,
    required this.action,
    required this.keys,
    this.desktopKey,
  });

  @override
  State<CallShortcutRow> createState() => _CallShortcutRowState();
}

class _CallShortcutRowState extends State<CallShortcutRow> {
  final FocusNode _focus = FocusNode();
  bool _capturing = false;

  /// Why the last press could not be a shortcut, if it could not.
  String? _refusal;

  @override
  void dispose() {
    CallShortcutListener.endCapture(this);
    _focus.dispose();
    super.dispose();
  }

  void _setCapturing(bool on) {
    if (!mounted || on == _capturing) return;
    if (on) {
      CallShortcutListener.startCapture(this);
    } else {
      CallShortcutListener.endCapture(this);
    }
    setState(() {
      _capturing = on;
      _refusal = null;
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
      setState(
        () => _refusal =
            'That key is for typing. Add Ctrl or Alt, or pick a key like F9.',
      );
      return KeyEventResult.handled;
    }
    final app = context.read<AppCubit>().state;
    if (app.pushToTalkEnabled && app.pushToTalkKeyId == keys.keyId) {
      setState(() => _refusal = 'Push-to-talk uses that key. Pick another.');
      return KeyEventResult.handled;
    }
    context.read<AppCubit>().setCallShortcut(widget.action, keys);
    _setCapturing(false);
    return KeyEventResult.handled;
  }

  String get _title => callShortcutTitle(widget.action);

  /// Whether [keys] work with Rift in the background, as the section says
  /// they do: on Windows a key the hook can name, on Linux one the desktop
  /// holds (none where there is no portal, or it said no).
  bool _heardAnywhere(KeyShortcut keys) {
    if (kIsWeb || !HostPlatform.hearsShortcutsAnywhere) return true;
    if (Platform.isWindows) return HookKeyState.hears(keys);
    if (Platform.isLinux) return _desktopHolds;
    return true;
  }

  bool get _desktopHolds => widget.desktopKey != null;

  /// The keys as Rift writes them, unless the desktop holds a key Rift cannot
  /// read: then the desktop's own words, since the stored keys are not the
  /// ones that work.
  String _shownKeys(KeyShortcut keys) {
    final desktop = widget.desktopKey;
    if (desktop == null || shortcutForTriggerDescription(desktop) != null) {
      return keys.label;
    }
    return desktop.replaceFirst(RegExp('^Press ', caseSensitive: false), '');
  }

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
                    _refusal ?? 'Press the keys together, like Ctrl+Shift+M.',
                    style: hint,
                  )
                else if (keys != null) ...[
                  Text(
                    _shownKeys(keys),
                    style: AppText.kbd.copyWith(color: theme.textSecondary),
                  ),
                  if (!_heardAnywhere(keys))
                    Text('Only while Rift is in front.', style: hint),
                  if (_desktopHolds && !DesktopShortcutSettings.canOpen)
                    Text(
                      "To change it, open your computer's settings and look "
                      "for Rift's keyboard shortcuts.",
                      style: hint,
                    ),
                ] else
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
          if (_desktopHolds && keys != null)
            DesktopShortcutSettings.canOpen
                ? const AppButton(
                    label: 'Change key',
                    variant: AppButtonVariant.secondary,
                    onPressed: DesktopShortcutSettings.open,
                  )
                : const SizedBox.shrink()
          else
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
