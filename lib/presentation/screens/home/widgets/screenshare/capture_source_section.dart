import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../src/rust/api/screenshare/types.dart';
import 'source_thumbnail_grid.dart';

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
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh $label list',
              onPressed: isLoading ? null : onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (sources == null || sources!.isEmpty)
          Text('No $label sources found.')
        else if (Platform.isWindows)
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
    final selectedSource =
        sources.where((s) => s.index == selectedIndex).firstOrNull;

    return DropdownButtonFormField<int>(
      key: ValueKey(
          '${captureFullScreen}_${selectedSource?.index}_${sources.length}'),
      initialValue: selectedSource?.index,
      isExpanded: true,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: sources
          .map((s) => DropdownMenuItem<int>(
                value: s.index,
                child: Text(_displayLabel(s, label),
                    overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      selectedItemBuilder: (context) => sources
          .map((s) => Align(
                alignment: Alignment.centerLeft,
                child: Text(_displayLabel(s, label),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (value) {
        if (value == null) return;
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

