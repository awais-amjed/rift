import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../src/rust/api/screenshare/audio_windows.dart';
import '../../../../theme/custom_colors.dart';
import 'settings_section.dart';

/// Section for selecting Windows audio source for screen sharing (WASAPI loopback).
class AudioSourceWindowsSection extends StatelessWidget {
  final List<AudioSourceWindows>? audioSources;
  final AudioSourceWindows? selectedAudioSource;
  final bool isLoading;
  final ValueChanged<AudioSourceWindows> onChanged;
  final VoidCallback onRefresh;

  const AudioSourceWindowsSection({
    super.key,
    required this.audioSources,
    required this.selectedAudioSource,
    required this.isLoading,
    required this.onChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return SettingsSection(
          label: 'Audio Source',
          children: [
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (audioSources == null || audioSources!.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: themeState.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No audio sources found. Make sure an application is open.',
                        style: TextStyle(
                          fontSize: 12,
                          color: themeState.textTertiary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onRefresh,
                      child: const Text('Refresh'),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: themeState.borderPrimary),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AudioSourceWindows>(
                    value: selectedAudioSource,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: themeState.textSecondary,
                    ),
                    dropdownColor: themeState.isDarkTheme
                        ? const Color(0xFF2A2A2E)
                        : CustomColors.bgSecondaryLight,
                    borderRadius: BorderRadius.circular(8),
                    hint: Text(
                      'Select audio source',
                      style: TextStyle(
                        fontSize: 13,
                        color: themeState.textTertiary,
                      ),
                    ),
                    items: audioSources!.map((source) {
                      return DropdownMenuItem<AudioSourceWindows>(
                        value: source,
                        child: Text(
                          source.title.isNotEmpty
                              ? source.title
                              : 'Unknown (PID: ${source.pid})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: themeState.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (source) {
                      if (source != null) {
                        onChanged(source);
                      }
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
