import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../common/app_button.dart';
import '../../../../common/button_footer.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';
import '../setting_toggle_row.dart';

/// Push-to-talk: the enable switch, the current keybind, and the capture
/// button that listens for the next key pressed.
///
/// Windows and Linux only ([HostPlatform.hasPushToTalk]); the Voice & Audio
/// tab omits the whole section elsewhere rather than showing controls that do
/// nothing. On Linux the key chosen here is only a suggestion to the desktop,
/// which asks the user to confirm it and owns it from then on — so the
/// section says so, or a key changed in the desktop's settings would look
/// like Rift ignoring this one.
class PushToTalkSection extends StatefulWidget {
  final AppState appState;

  const PushToTalkSection({super.key, required this.appState});

  @override
  State<PushToTalkSection> createState() => _PushToTalkSectionState();
}

class _PushToTalkSectionState extends State<PushToTalkSection> {
  static final bool _isLinux = !kIsWeb && Platform.isLinux;

  final FocusNode _captureFocusNode = FocusNode();
  bool _isCapturing = false;

  @override
  void dispose() {
    _captureFocusNode.dispose();
    super.dispose();
  }

  void _toggleCapture(bool enabled) {
    if (!mounted) return;
    setState(() => _isCapturing = enabled);
    if (enabled) {
      _captureFocusNode.requestFocus();
    } else {
      _captureFocusNode.unfocus();
    }
  }

  /// Something readable for any key, including ones with no printable label.
  String _labelForKey(LogicalKeyboardKey key) {
    final label = key.keyLabel.trim();
    if (label.isNotEmpty) return label;
    final debugName = key.debugName?.trim();
    if (debugName != null && debugName.isNotEmpty) return debugName;
    return 'Unknown key';
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (!_isCapturing || event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _toggleCapture(false);
      return KeyEventResult.handled;
    }

    context.read<AppCubit>().setPushToTalkKeybind(
      keyId: event.logicalKey.keyId,
      label: _labelForKey(event.logicalKey),
    );
    _toggleCapture(false);
    return KeyEventResult.handled;
  }

  /// The key the desktop reports while it owns push-to-talk, without its
  /// "Press " prefix so it reads like any other keybind.
  String? get _desktopKey =>
      widget.appState.desktopPushToTalkKey?.replaceFirst(RegExp('^Press '), '');

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final appState = widget.appState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(label: 'Push-to-talk'),
        const SizedBox(height: 12),
        SettingToggleRow(
          title: 'Enable push-to-talk',
          description: 'Hold the configured key to transmit your mic.',
          value: appState.pushToTalkEnabled,
          onChanged: context.read<AppCubit>().setPushToTalkEnabled,
        ),
        const SizedBox(height: 16),
        Text(
          'KEYBIND',
          style: AppText.sectionLabel.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 6),
        Text(
          _desktopKey ?? appState.pushToTalkKeyLabel ?? 'Not set',
          style: AppText.kbd.copyWith(color: themeState.textSecondary),
        ),
        const SizedBox(height: 10),
        if (_desktopKey != null)
          Text(
            'Set by your desktop, which now owns this key. To change it, use '
            'the shortcuts for Rift in your system settings.',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          )
        else
          Focus(
            focusNode: _captureFocusNode,
            onKeyEvent: _onKeyEvent,
            child: ButtonFooter(
              alignment: MainAxisAlignment.start,
              buttons: [
                AppButton(
                  label: 'Clear',
                  onPressed: appState.pushToTalkKeyId == null
                      ? null
                      : context.read<AppCubit>().clearPushToTalkKeybind,
                  variant: AppButtonVariant.secondary,
                ),
                AppButton(
                  label: _isCapturing ? 'Press a key…' : 'Set key',
                  onPressed: () => _toggleCapture(!_isCapturing),
                  variant: _isCapturing
                      ? AppButtonVariant.secondary
                      : AppButtonVariant.primary,
                ),
              ],
            ),
          ),
        if (_isLinux && _desktopKey == null) ...[
          const SizedBox(height: 8),
          Text(
            'Your desktop asks once to let Rift use this key in other apps. '
            'You can change or revoke it later in your system settings.',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          ),
        ],
        if (_isCapturing) ...[
          const SizedBox(height: 8),
          Text(
            'Press Esc to cancel key capture.',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          ),
        ],
      ],
    );
  }
}
