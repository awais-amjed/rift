import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';

Future<void> showSettingsDialog(BuildContext context) async {
  await showAppModal<void>(context: context, modal: const _SettingsDialog());
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
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
    if (debugName != null && debugName.trim().isNotEmpty) {
      return debugName;
    }
    return 'Unknown key';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<AppCubit, AppState>(
          builder: (context, appState) {
            final keybindLabel = appState.pushToTalkKeyLabel ?? 'Not set';
            final canUsePtt = !kIsWeb && Platform.isWindows;

            return AppModal(
              title: 'Settings',
              subtitle: 'Configure voice input behavior.',
              titleIcon: Icon(
                Icons.settings_outlined,
                size: 20,
                color: themeState.textPrimary,
              ),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
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
                            ? (value) => context
                                  .read<AppCubit>()
                                  .setPushToTalkEnabled(value)
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
                    style: TextStyle(
                      color: themeState.textSecondary,
                      fontSize: 13,
                    ),
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
                      this.context.read<AppCubit>().setPushToTalkKeybind(
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
                      style: TextStyle(
                        color: themeState.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                AppButton(
                  label: 'Done',
                  onPressed: () => Navigator.of(context).pop(),
                  variant: AppButtonVariant.primary,
                ),
              ],
            );
          },
        );
      },
    );
  }
}



