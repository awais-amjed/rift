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

  /// Whether the list fills a height it was given and scrolls in it, rather
  /// than growing to fit inside the dialog's own scroll.
  final bool fills;

  const CaptureSourceSection({
    super.key,
    required this.captureFullScreen,
    required this.isLoading,
    required this.sources,
    required this.selectedIndex,
    required this.thumbnails,
    required this.onChanged,
    required this.onRefresh,
    this.fills = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = captureFullScreen ? 'Screen' : 'Window';

    final list = _list();
    return Column(
      mainAxisSize: fills ? MainAxisSize.max : MainAxisSize.min,
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
        if (fills && list is SourceThumbnailGrid)
          Expanded(child: list)
        else
          list,
      ],
    );
  }

  Widget _list() {
    final label = captureFullScreen ? 'Screen' : 'Window';
    if (isLoading) return const LinearProgressIndicator(minHeight: 2);
    final found = sources;
    if (found == null || found.isEmpty) return Text('No $label sources found.');
    if (HostPlatform.hasShareThumbnails) {
      return SourceThumbnailGrid(
        sources: found,
        selectedIndex: selectedIndex,
        thumbnails: thumbnails,
        captureFullScreen: captureFullScreen,
        onChanged: onChanged,
        scrolls: fills,
      );
    }
    return _SourceDropdown(
      sources: found,
      selectedIndex: selectedIndex,
      captureFullScreen: captureFullScreen,
      onChanged: onChanged,
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
