import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../src/rust/api/screenshare/types.dart';
import '../widgets/settings_section.dart';
import '../../../../theme/app_text.dart';

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
                        style: AppText.secondary.copyWith(
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
                  child: DropdownButton<AudioSource>(
                    value: selectedAudioSource,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: themeState.textSecondary,
                    ),
                    dropdownColor: themeState.bgElevated,
                    borderRadius: BorderRadius.circular(8),
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
      },
    );
  }
}
