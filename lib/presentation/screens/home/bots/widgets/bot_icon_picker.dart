import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/directory_icon.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// The picture on a bot's listing, and the control for changing it.
///
/// Shows, in order of what is true: the picture just picked, the one already
/// on the listing, or the bot's initial. The last is not a placeholder — a
/// listing with no icon draws exactly that in the browser, so what is on
/// screen here is what a stranger will see.
class BotIconPicker extends StatelessWidget {
  /// Bytes chosen in this session, not yet uploaded.
  final Uint8List? picked;

  /// The icon already stored on the listing being edited, if any.
  final String? iconPath;

  /// Supplies the initial and its gradient when there is no picture.
  final String name;

  /// Stable id picking that gradient, so renaming does not recolour it.
  final String? seed;

  final VoidCallback onPick;
  final VoidCallback? onClear;

  const BotIconPicker({
    super.key,
    required this.picked,
    required this.iconPath,
    required this.name,
    required this.onPick,
    this.seed,
    this.onClear,
  });

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final hasPicture = picked != null || iconPath != null;

    return Row(
      children: [
        _preview(),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Icon',
                style: AppText.label.copyWith(color: theme.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                // Says where it goes, because a directory that fetched the
                // picture from somewhere else is what this replaced.
                'Optional. Stored with the listing, so browsing the '
                'directory never asks your server for it.',
                style: AppText.secondary.copyWith(color: theme.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: onPick,
          child: Text(hasPicture ? 'Change' : 'Choose'),
        ),
        if (hasPicture && onClear != null)
          TextButton(
            onPressed: onClear,
            child: Text(
              'Remove',
              style: TextStyle(color: theme.textTertiary),
            ),
          ),
      ],
    );
  }

  Widget _preview() {
    final bytes = picked;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_size * K.avatarRadiusRatio),
        child: Image.memory(
          bytes,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    return DirectoryIcon(
      iconPath: iconPath,
      name: name,
      seed: seed,
      size: _size,
    );
  }
}
