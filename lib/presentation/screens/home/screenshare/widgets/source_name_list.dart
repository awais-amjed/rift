import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/services/screen_share_sources.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';

/// The windows or screens to pick from, by name: where the app lists them
/// itself and has no pictures of them (X11, macOS).
class SourceNameList extends StatelessWidget {
  final List<CaptureSource> sources;
  final int? selectedIndex;
  final bool captureFullScreen;
  final ValueChanged<CaptureSource> onChanged;

  const SourceNameList({
    super.key,
    required this.sources,
    required this.selectedIndex,
    required this.captureFullScreen,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: sources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final source = sources[i];
        final selected = source.index == selectedIndex;
        return SizedBox(
          height: K.controlHeight,
          child: Semantics(
            selected: selected,
            child: SelectableSurface(
              selected: selected,
              onTap: () => onChanged(source),
              borderRadius: BorderRadius.circular(K.radiusRow),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                spacing: 10,
                children: [
                  Icon(
                    captureFullScreen
                        ? Icons.desktop_windows_outlined
                        : Icons.web_asset,
                    size: K.iconRow,
                  ),
                  Expanded(
                    child: Text(
                      ScreenShareSources.labelOf(source, captureFullScreen),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: selected ? AppText.row : AppText.rowQuiet,
                    ),
                  ),
                  if (selected) const Icon(Icons.check, size: K.iconRow),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
