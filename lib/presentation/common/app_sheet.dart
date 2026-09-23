import 'package:flutter/material.dart';

import '../responsive/compact_only.dart';
import '../theme/theme_context.dart';
import 'popover_surface.dart';

/// Open [child] as the bottom sheet a phone uses in place of a dialog.
///
/// One place, because the settings a sheet needs are not obvious and getting
/// one of them wrong is silent: without `isScrollControlled` a tall sheet is
/// cut off at half the screen, and without a background the modal it contains
/// draws straight over whatever is behind it.
///
/// A sheet is the phone's shape for a dialog and has no wide form, so it is
/// wrapped in a [CompactOnly]: widening the window past the breakpoint
/// closes it rather than leaving it stranded over chrome that has come back.
///
/// [child] is built by the caller while its context is still mounted — a
/// route rebuilds for reasons that have nothing to do with what opened it,
/// and reading cubits inside the builder is how a resize becomes "Looking up
/// a deactivated widget's ancestor".
Future<T?> showAppSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.theme.bgSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PopoverSurface.radius),
      ),
    ),
    builder: (_) => CompactOnly(child: child),
  );
}
