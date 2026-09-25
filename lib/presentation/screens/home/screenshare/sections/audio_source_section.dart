import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/loading_dots.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../widgets/settings_section.dart';

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

  String _buildLabel(AudioSource source) {
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
    final themeState = context.theme;
    return SettingsSection(
      label: 'Audio source',
      children: [
        if (isLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LoadingDots(color: context.theme.accentBright, dotSize: 4),
            ),
          )
        else if (audioSources == null || audioSources!.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: K.iconRow,
                  color: themeState.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No audio sources found. Make sure an application is playing audio.',
                    style: AppText.secondary.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
                ),
                TextButton(onPressed: onRefresh, child: const Text('Refresh')),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(K.radiusRow),
              border: Border.all(color: themeState.borderPrimary),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AudioSource>(
                value: selectedAudioSource,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                icon: Icon(
                  Icons.arrow_drop_down,
                  color: themeState.textSecondary,
                ),
                dropdownColor: themeState.bgElevated,
                borderRadius: BorderRadius.circular(K.radiusRow),
                hint: Text(
                  'Select audio source',
                  style: AppText.rowQuiet.copyWith(
                    color: themeState.textTertiary,
                  ),
                ),
                items: audioSources!.map((source) {
                  return DropdownMenuItem<AudioSource>(
                    value: source,
                    child: Text(
                      _buildLabel(source),
                      style: AppText.rowQuiet.copyWith(
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
  }
}
