import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';

Future<void> showSettingsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _SettingsDialog(),
  );
}

// ─────────────────────────────────────────────────────────────
// Root dialog
// ─────────────────────────────────────────────────────────────

enum _SettingsTab { appearance, voiceAndAudio }

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  _SettingsTab _activeTab = _SettingsTab.appearance;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Dialog(
          backgroundColor: themeState.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: themeState.borderPrimary),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 520),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left sidebar ──────────────────────────────
                _SettingsSidebar(
                  activeTab: _activeTab,
                  onTabSelected: (tab) => setState(() => _activeTab = tab),
                  themeState: themeState,
                ),
                // Divider
                VerticalDivider(
                  width: 1,
                  color: themeState.borderPrimary,
                ),
                // ── Right content area ────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                        child: Row(
                          children: [
                            Icon(
                              _activeTab == _SettingsTab.appearance
                                  ? Icons.palette_outlined
                                  : Icons.headset_outlined,
                              size: 20,
                              color: themeState.textPrimary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _activeTab == _SettingsTab.appearance
                                        ? 'Appearance'
                                        : 'Voice & Audio',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: themeState.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _activeTab == _SettingsTab.appearance
                                        ? 'Customize the look of the app.'
                                        : 'Configure voice input behavior.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: themeState.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(
                                Icons.close,
                                color: themeState.textTertiary,
                                size: 20,
                              ),
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: themeState.borderPrimary),
                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: _activeTab == _SettingsTab.appearance
                              ? _AppearanceContent(themeState: themeState)
                              : _VoiceAudioContent(themeState: themeState),
                        ),
                      ),
                      // Footer
                      Divider(height: 1, color: themeState.borderPrimary),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: AppButton(
                          label: 'Done',
                          onPressed: () => Navigator.of(context).pop(),
                          variant: AppButtonVariant.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────

class _SettingsSidebar extends StatelessWidget {
  final _SettingsTab activeTab;
  final ValueChanged<_SettingsTab> onTabSelected;
  final ThemeState themeState;

  const _SettingsSidebar({
    required this.activeTab,
    required this.onTabSelected,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 18,
                  color: themeState.textTertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: themeState.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          _SidebarItem(
            icon: Icons.palette_outlined,
            label: 'Appearance',
            isActive: activeTab == _SettingsTab.appearance,
            themeState: themeState,
            onTap: () => onTabSelected(_SettingsTab.appearance),
          ),
          _SidebarItem(
            icon: Icons.headset_outlined,
            label: 'Voice & Audio',
            isActive: activeTab == _SettingsTab.voiceAndAudio,
            themeState: themeState,
            onTap: () => onTabSelected(_SettingsTab.voiceAndAudio),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final ThemeState themeState;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.themeState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = themeState.channelActiveText;
    final activeBg = themeState.channelActiveBg;
    final textColor =
        isActive ? activeColor : themeState.textSecondary;
    final bgColor = isActive ? activeBg : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 17, color: textColor),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Appearance tab
// ─────────────────────────────────────────────────────────────

class _AppearanceContent extends StatelessWidget {
  final ThemeState themeState;

  const _AppearanceContent({required this.themeState});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Theme',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: themeState.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _ThemeCard(
              label: 'Dark',
              icon: Icons.dark_mode_outlined,
              isSelected: themeState.isDarkTheme,
              themeState: themeState,
              onTap: () =>
                  context.read<ThemeCubit>().setTheme(ThemeMode.dark),
            ),
            const SizedBox(width: 12),
            _ThemeCard(
              label: 'Light',
              icon: Icons.light_mode_outlined,
              isSelected: themeState.isLightTheme,
              themeState: themeState,
              onTap: () =>
                  context.read<ThemeCubit>().setTheme(ThemeMode.light),
            ),
          ],
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final ThemeState themeState;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.themeState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? themeState.channelActiveBorder
        : themeState.borderPrimary;
    final bgColor =
        isSelected ? themeState.channelActiveBg : themeState.bgTertiary;
    final textColor =
        isSelected ? themeState.channelActiveText : themeState.textSecondary;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 110,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: textColor),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Voice & Audio tab
// ─────────────────────────────────────────────────────────────

class _VoiceAudioContent extends StatefulWidget {
  final ThemeState themeState;

  const _VoiceAudioContent({required this.themeState});

  @override
  State<_VoiceAudioContent> createState() => _VoiceAudioContentState();
}

class _VoiceAudioContentState extends State<_VoiceAudioContent> {
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
                      onPressed:
                          canUsePtt ? () => _toggleCapture(!_isCapturing) : null,
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
        );
      },
    );
  }
}
