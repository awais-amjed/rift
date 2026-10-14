import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/app_dropdown.dart';
import '../../../../common/loading_dots.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../widgets/settings_section.dart';

/// Which apps a Linux screen share is heard from: every app but Rift — no
/// source, and the first choice — or the one app picked.
class AudioSourceSection extends StatelessWidget {
  final List<AudioSource>? audioSources;
  final AudioSource? selectedAudioSource;
  final bool isLoading;

  /// Null for every app but Rift.
  final ValueChanged<AudioSource?> onChanged;
  final VoidCallback onRefresh;

  const AudioSourceSection({
    super.key,
    required this.audioSources,
    required this.selectedAudioSource,
    required this.isLoading,
    required this.onChanged,
    required this.onRefresh,
  });

  static const allApps = 'All apps (except Rift)';

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
    final sources = audioSources ?? const <AudioSource>[];
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
        else ...[
          AppDropdown<AudioSource?>(
            value: selectedAudioSource,
            hint: allApps,
            options: [
              const AppDropdownOption(value: null, label: allApps),
              for (final source in sources)
                AppDropdownOption(value: source, label: _buildLabel(source)),
            ],
            onChanged: onChanged,
          ),
          // An app that starts later is heard anyway; this is only for
          // picking it on its own.
          if (sources.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
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
                      'No app is playing sound right now.',
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
            ),
        ],
      ],
    );
  }
}
