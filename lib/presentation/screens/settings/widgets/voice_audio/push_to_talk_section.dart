import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/ptt/mouse_button_bind.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../common/app_button.dart';
import '../../../../common/button_footer.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';
import '../setting_toggle_row.dart';
import 'desktop_key_notice.dart';

/// Push-to-talk: the enable switch, the current keybind, and the capture
/// button that listens for the next key or mouse button pressed.
///
/// Any key is accepted, Esc included, and any mouse button but the left —
/// the capture is cancelled by clicking its button again, which is why the
/// left one can never be the answer. Buttons are heard app-wide through the
/// pointer router, because the pointer is rarely over the button itself.
///
/// The keybind only appears with push-to-talk on. On Linux the desktop
/// answers with the key it already granted the moment it is switched on, so
/// a key picked while it was off would be quietly replaced — and holding
/// every platform to the same rule keeps the screen predictable.
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
  final FocusNode _captureFocusNode = FocusNode();
  bool _isCapturing = false;

  /// Listening for a mouse button only — where the desktop owns the key, a
  /// key pressed here would be swapped back for the desktop's.
  bool _mouseOnly = false;

  /// The key is only picked with push-to-talk on — see [build] — so turning
  /// it off mid-capture ends the capture rather than leaving it listening.
  @override
  void didUpdateWidget(PushToTalkSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isCapturing && !widget.appState.pushToTalkEnabled) {
      _toggleCapture(false);
    }
  }

  @override
  void dispose() {
    if (_isCapturing) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    }
    _captureFocusNode.dispose();
    super.dispose();
  }

  void _toggleCapture(bool enabled, {bool mouseOnly = false}) {
    if (!mounted || enabled == _isCapturing) return;
    final router = GestureBinding.instance.pointerRouter;
    if (enabled) {
      router.addGlobalRoute(_onPointer);
    } else {
      router.removeGlobalRoute(_onPointer);
    }
    setState(() {
      _isCapturing = enabled;
      _mouseOnly = enabled && mouseOnly;
    });
    if (enabled && !mouseOnly) {
      _captureFocusNode.requestFocus();
    } else {
      _captureFocusNode.unfocus();
    }
  }

  void _onPointer(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse || event is PointerUpEvent) {
      return;
    }
    final button = MouseButtonBind.pick(event.buttons);
    if (button == null) return;
    context.read<AppCubit>().setPushToTalkKeybind(
      keyId: MouseButtonBind.keyIdFor(button),
      label: MouseButtonBind.label(button),
    );
    _toggleCapture(false);
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
    // Not a key the user pressed. On Linux the first key event after focus
    // makes Flutter catch its lock-key state up with the OS, and with Num Lock
    // on that arrives as a made-up Num Lock press — which the capture took as
    // the keybind every first time.
    if (event.synthesized) return KeyEventResult.ignored;

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

  bool get _boundToMouse {
    final keyId = widget.appState.pushToTalkKeyId;
    return keyId != null && MouseButtonBind.isMouse(keyId);
  }

  /// Whether the desktop, not this section, decides the key — known, or
  /// being asked for.
  bool get _desktopOwnsKey =>
      _desktopKey != null || widget.appState.desktopPushToTalkPending;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final appState = widget.appState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Push-to-talk'),
        const SizedBox(height: 12),
        SettingToggleRow(
          title: 'Enable push-to-talk',
          description: 'Hold the configured key to transmit your mic.',
          value: appState.pushToTalkEnabled,
          onChanged: context.read<AppCubit>().setPushToTalkEnabled,
        ),
        if (appState.pushToTalkEnabled) ...[
          const SizedBox(height: 16),
          Text(
            'KEYBIND',
            style: AppText.sectionLabel.copyWith(
              color: themeState.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _desktopKey ?? appState.pushToTalkKeyLabel ?? 'Not set',
            style: AppText.kbd.copyWith(color: themeState.textSecondary),
          ),
          const SizedBox(height: 10),
          if (_desktopOwnsKey)
            DesktopKeyNotice(
              pending: appState.desktopPushToTalkPending,
              capturingMouse: _isCapturing,
              onUseMouse: () => _toggleCapture(!_isCapturing, mouseOnly: true),
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
                    label: _isCapturing ? 'Cancel' : 'Set key',
                    onPressed: () => _toggleCapture(!_isCapturing),
                    variant: _isCapturing
                        ? AppButtonVariant.secondary
                        : AppButtonVariant.primary,
                  ),
                ],
              ),
            ),
          if (HostPlatform.pushToTalkAsksDesktop && !_desktopOwnsKey) ...[
            const SizedBox(height: 8),
            Text(
              _boundToMouse
                  ? 'A mouse button works only while the pointer is over '
                        'Rift. A key works in other apps too.'
                  : 'After you set a key, your computer asks once whether '
                        'Rift may use it while you are in other apps.',
              style: AppText.secondary.copyWith(color: themeState.textTertiary),
            ),
          ],
        ],
        if (_isCapturing) ...[
          const SizedBox(height: 8),
          Text(
            _mouseOnly
                ? 'Press the mouse button to use. The left one is for '
                      'clicking, so it cannot be used.'
                : 'Press any key or mouse button. The left button is for '
                      'clicking, so it cannot be used.',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          ),
        ],
      ],
    );
  }
}
