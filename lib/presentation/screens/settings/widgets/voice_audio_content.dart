import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import 'audio_device_section.dart';

class VoiceAudioContent extends StatefulWidget {
  final ThemeState themeState;

  const VoiceAudioContent({super.key, required this.themeState});

  @override
  State<VoiceAudioContent> createState() => _VoiceAudioContentState();
}

class _VoiceAudioContentState extends State<VoiceAudioContent> {
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

  String _labelForKey(LogicalKeyboardKey key) {
    final label = key.keyLabel.trim();
    if (label.isNotEmpty) return label;
    final debugName = key.debugName;
    if (debugName != null && debugName.trim().isNotEmpty) return debugName;
    return 'Unknown key';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, appState) {
        final themeState = widget.themeState;
        final keybindLabel = appState.pushToTalkKeyLabel ?? 'Not set';
        final canUsePtt = !kIsWeb && Platform.isWindows;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Audio Devices ────────────────────────────────
            AudioDeviceSection(themeState: themeState),
            const SizedBox(height: 24),
            Divider(color: themeState.borderPrimary),
            const SizedBox(height: 16),
            // ── Audio Ducking (Windows only) ─────────────────
            if (!kIsWeb && Platform.isWindows) ...[
              Text(
                'Audio Ducking',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: themeState.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Disable automatic volume lowering',
                          style: TextStyle(
                            color: themeState.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Windows lowers other apps\' volume when a call is active. '
                          'Enable this to prevent that.',
                          style: TextStyle(
                            color: themeState.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: appState.disableAudioDucking,
                    onChanged: (value) =>
                        context.read<AppCubit>().setDisableAudioDucking(value),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: themeState.borderPrimary),
              const SizedBox(height: 16),
            ],
            // ── Push-to-Talk ─────────────────────────────────
            Text(
              'Push-to-Talk',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: themeState.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enable Push-to-Talk',
                        style: TextStyle(
                          color: themeState.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        canUsePtt
                            ? 'Hold the configured key to transmit your mic.'
                            : 'Push-to-talk is currently available on Windows only.',
                        style: TextStyle(
                          color: themeState.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: appState.pushToTalkEnabled,
                  onChanged: canUsePtt
                      ? (value) =>
                            context.read<AppCubit>().setPushToTalkEnabled(value)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Keybind',
              style: TextStyle(
                color: themeState.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              keybindLabel,
              style: TextStyle(color: themeState.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Focus(
              focusNode: _captureFocusNode,
              onKeyEvent: (_, event) {
                if (!_isCapturing || event is! KeyDownEvent) {
                  return KeyEventResult.ignored;
                }

                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  _toggleCapture(false);
                  return KeyEventResult.handled;
                }

                final key = event.logicalKey;
                context.read<AppCubit>().setPushToTalkKeybind(
                  keyId: key.keyId,
                  label: _labelForKey(key),
                );
                _toggleCapture(false);
                return KeyEventResult.handled;
              },
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: _isCapturing
                          ? 'Press any key...'
                          : 'Set Push-to-Talk Key',
                      onPressed: canUsePtt
                          ? () => _toggleCapture(!_isCapturing)
                          : null,
                      variant: _isCapturing
                          ? AppButtonVariant.secondary
                          : AppButtonVariant.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: 'Clear',
                    onPressed: appState.pushToTalkKeyId == null
                        ? null
                        : () =>
                              context.read<AppCubit>().clearPushToTalkKeybind(),
                    variant: AppButtonVariant.secondary,
                  ),
                ],
              ),
            ),
            if (_isCapturing) ...[
              const SizedBox(height: 8),
              Text(
                'Press Esc to cancel key capture.',
                style: TextStyle(color: themeState.textTertiary, fontSize: 12),
              ),
            ],
          ],
        );
      },
    );
  }
}
