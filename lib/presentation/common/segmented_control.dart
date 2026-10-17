import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_text.dart';
import 'selectable_surface.dart';

/// One choice in a [SegmentedControl].
class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SegmentOption({required this.value, required this.label, this.icon});
}

/// A two- or three-way choice, named up front: text / voice, sign in / create
/// account, person / bot, dark / light.
///
/// Equal-width segments on the app's one selection language. Used where the
/// choice shapes what follows — a form that grows a confirm field, an invite
/// that mints a different kind of thing — so it is asked first rather than
/// discovered as a link at the bottom or a switch between the fields.
///
/// Where the labels do not fit side by side — five noise filters on a phone —
/// the segments go onto rows of as even a length as the width allows (three
/// and two), still equal widths and lined up in columns, rather than every
/// name cut down to its first few letters.
class SegmentedControl<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;

  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  static const double _gap = 8;
  static const double _padding = 8;
  static const double _iconGap = 7;

  /// How many segments one row holds at [width] without cutting a label
  /// short, judged by the widest label in its selected (heavier) style.
  int _perRow(BuildContext context, double width) {
    if (!width.isFinite) return options.length;
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final option in options) {
      final painter = TextPainter(
        text: TextSpan(text: option.label, style: AppText.row),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final icon = option.icon == null ? 0.0 : K.iconRow + _iconGap;
      widest = max(widest, painter.width + icon);
      painter.dispose();
    }
    // Both sides' padding, and the selection border's pixel either side.
    final segment = widest + _padding * 2 + 2;
    return ((width + _gap) / (segment + _gap)).floor().clamp(1, options.length);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = _perRow(context, constraints.maxWidth);
        if (perRow >= options.length) return _row(options, options.length);
        final rows = (options.length / perRow).ceil();
        final even = (options.length / rows).ceil();
        return Column(
          mainAxisSize: MainAxisSize.min,
          spacing: _gap,
          children: [
            for (var i = 0; i < options.length; i += even)
              _row(options.sublist(i, min(i + even, options.length)), even),
          ],
        );
      },
    );
  }

  /// [row] in [slots] equal columns; a short last row leaves its end empty
  /// so the segments stay lined up with the ones above.
  Widget _row(List<SegmentOption<T>> row, int slots) => Row(
    spacing: _gap,
    children: [
      for (final option in row) Expanded(child: _segment(option)),
      for (var i = row.length; i < slots; i++) const Spacer(),
    ],
  );

  // The field height, not padding around the label: an option sits in a form
  // beside fields and has to line up with them.
  Widget _segment(SegmentOption<T> option) => SizedBox(
    height: K.fieldHeight,
    child: SelectableSurface(
      selected: option.value == value,
      onTap: onChanged == null ? null : () => onChanged!(option.value),
      borderRadius: BorderRadius.circular(K.radiusRow),
      padding: const EdgeInsets.symmetric(horizontal: _padding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: _iconGap,
        children: [
          if (option.icon != null) Icon(option.icon, size: K.iconRow),
          // Flexible, so a label too long even for a row of its own ellipsises
          // instead of pushing the segment wider than its column.
          Flexible(
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: option.value == value ? AppText.row : AppText.rowQuiet,
            ),
          ),
        ],
      ),
    ),
  );
}
