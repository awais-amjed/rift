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

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        for (final option in options)
          Expanded(
            child: SelectableSurface(
              selected: option.value == value,
              onTap: onChanged == null ? null : () => onChanged!(option.value),
              borderRadius: BorderRadius.circular(K.radiusRow),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 7,
                children: [
                  if (option.icon != null) Icon(option.icon, size: 15),
                  // Flexible, so a long label on a narrow phone ellipsises
                  // instead of pushing the segment wider than its half.
                  Flexible(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: option.value == value
                          ? AppText.row
                          : AppText.rowQuiet,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
