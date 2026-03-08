import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../src/rust/api/screenshare/audio_linux.dart';
import '../../../../theme/custom_colors.dart';
import 'settings_section.dart';

/// Section for selecting Linux audio source for screen sharing
class AudioSourceSection extends StatelessWidget {
  final List<AudioSource>? audioSources;
  final AudioSource? selectedAudioSource;
  final bool isLoading;
  final ValueChanged<AudioSource> onChanged;
  final VoidCallback onRefresh;

  const AudioSourceSection({
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
                        'No audio sources found. Make sure an application is playing audio.',
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
              Column(
                children: [
                  for (final source in audioSources!)
                    _AudioSourceItem(
                      source: source,
                      isSelected: selectedAudioSource == source,
                      onTap: () => onChanged(source),
                      themeState: themeState,
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Individual audio source item
class _AudioSourceItem extends StatelessWidget {
  final AudioSource source;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeState themeState;

  const _AudioSourceItem({
    required this.source,
    required this.isSelected,
    required this.onTap,
    required this.themeState,
  });

  String _buildLabel() {
    final mainLabel = source.mediaName.isNotEmpty
        ? source.mediaName
        : source.appName.isNotEmpty
        ? source.appName
        : 'Unknown';

    if (source.binary.isNotEmpty) {
      return '$mainLabel (${source.binary})';
    }
    return mainLabel;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? CustomColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? CustomColors.primary : themeState.borderPrimary,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: isSelected
                  ? CustomColors.primary
                  : themeState.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _buildLabel(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: themeState.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
