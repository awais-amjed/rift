import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../../src/rust/api/screenshare/types.dart';

/// Thumbnail grid for selecting a capture source (Windows only).
class SourceThumbnailGrid extends StatelessWidget {
  final List<CaptureSource> sources;
  final int? selectedIndex;
  final Map<int, Uint8List> thumbnails;
  final bool captureFullScreen;
  final ValueChanged<CaptureSource> onChanged;

  const SourceThumbnailGrid({
    super.key,
    required this.sources,
    required this.selectedIndex,
    required this.thumbnails,
    required this.captureFullScreen,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Screens: 2 columns (usually 1–3).
    // Windows: 3 columns (can be many).
    final crossAxisCount = captureFullScreen ? 2 : 3;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        // 16:9 preview with a label strip below
        childAspectRatio: 16 / 11,
      ),
      itemCount: sources.length,
      itemBuilder: (context, i) {
        final source = sources[i];
        return _SourceCard(
          source: source,
          isSelected: source.index == selectedIndex,
          thumbnail: thumbnails[source.index],
          label: _displayLabel(source),
          onTap: () => onChanged(source),
        );
      },
    );
  }

  String _displayLabel(CaptureSource source) {
    final typeLabel = captureFullScreen ? 'Screen' : 'Window';
    final trimmed = source.title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return '$typeLabel #${source.index + 1}';
  }
}

// ── Card ─────────────────────────────────────────────────────────────────────

class _SourceCard extends StatelessWidget {
  final CaptureSource source;
  final bool isSelected;
  final Uint8List? thumbnail;
  final String label;
  final VoidCallback onTap;

  const _SourceCard({
    required this.source,
    required this.isSelected,
    required this.thumbnail,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: isSelected ? 2.5 : 1.0,
          ),
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.08)
              : colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          children: [
            // Preview area
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(7)),
                child: thumbnail != null
                    ? Image.memory(
                        thumbnail!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        gaplessPlayback: true,
                      )
                    : Center(
                        child: Icon(
                          Icons.desktop_windows_outlined,
                          size: 28,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4),
                        ),
                      ),
              ),
            ),
            // Label strip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.normal,
                  color:
                      isSelected ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

