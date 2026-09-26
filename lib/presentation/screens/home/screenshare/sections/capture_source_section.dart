import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/app_dropdown.dart';
import '../widgets/source_thumbnail_grid.dart';

/// Section for selecting the capture source (screen or window).
///
/// On Windows a thumbnail grid is shown; on other platforms a dropdown is used.
class CaptureSourceSection extends StatelessWidget {
  final bool captureFullScreen;
  final bool isLoading;
  final List<CaptureSource>? sources;
  final int? selectedIndex;
  final Map<int, Uint8List> thumbnails;
  final ValueChanged<CaptureSource> onChanged;
  final Future<void> Function() onRefresh;

  const CaptureSourceSection({
    super.key,
    required this.captureFullScreen,
    required this.isLoading,
    required this.sources,
    required this.selectedIndex,
    required this.thumbnails,
    required this.onChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final label = captureFullScreen ? 'Screen' : 'Window';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Select $label',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh $label list',
              onPressed: isLoading ? null : onRefresh,
              icon: const Icon(Icons.refresh, size: K.iconButton),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (sources == null || sources!.isEmpty)
          Text('No $label sources found.')
        else if (HostPlatform.hasShareThumbnails)
          SourceThumbnailGrid(
            sources: sources!,
            selectedIndex: selectedIndex,
            thumbnails: thumbnails,
            captureFullScreen: captureFullScreen,
            onChanged: onChanged,
          )
        else
          _SourceDropdown(
            sources: sources!,
            selectedIndex: selectedIndex,
            captureFullScreen: captureFullScreen,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

// ── Dropdown fallback (Linux / non-Windows) ───────────────────────────────────

class _SourceDropdown extends StatelessWidget {
  final List<CaptureSource> sources;
  final int? selectedIndex;
  final bool captureFullScreen;
  final ValueChanged<CaptureSource> onChanged;

  const _SourceDropdown({
    required this.sources,
    required this.selectedIndex,
    required this.captureFullScreen,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = captureFullScreen ? 'Screen' : 'Window';
    final selectedSource = sources
        .where((s) => s.index == selectedIndex)
        .firstOrNull;

    return AppDropdown<int?>(
      value: selectedSource?.index,
      hint: 'Choose a ${label.toLowerCase()}',
      options: [
        for (final s in sources)
          AppDropdownOption(value: s.index, label: _displayLabel(s, label)),
      ],
      onChanged: (value) {
        final source = sources.where((s) => s.index == value).firstOrNull;
        if (source != null) onChanged(source);
      },
    );
  }

  String _displayLabel(CaptureSource source, String label) {
    final trimmed = source.title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return '$label #${source.index + 1} (index ${source.index})';
  }
}
