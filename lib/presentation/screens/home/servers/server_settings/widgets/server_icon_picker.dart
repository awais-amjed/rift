import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/constants.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/rounded_picture.dart';
import '../../../../../common/server_icon.dart';
import '../../../../../common/squircle_avatar.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// The server's icon, and the buttons that change it.
///
/// Nothing here writes. A picked picture and a removal are both held by the
/// page until Save, which uploads the one and writes the row once with the
/// name, so the form saves as one thing, as the profile dialog does.
class ServerIconPicker extends StatelessWidget {
  final Server server;

  /// The name as typed, for the initial while there is no picture.
  final String name;

  /// A picked picture waiting for Save.
  final Uint8List? picked;

  /// Whether Save will take the icon away.
  final bool removing;

  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  static const double _size = 56;

  const ServerIconPicker({
    super.key,
    required this.server,
    required this.name,
    required this.picked,
    required this.removing,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final picked = this.picked;
    final hasIcon = picked != null || (!removing && server.iconPath != null);
    final status = picked != null
        ? 'New icon ready to save'
        : removing
        ? 'The icon goes when you save'
        : null;

    return Row(
      spacing: 14,
      children: [
        if (picked != null)
          RoundedPicture(
            image: MemoryImage(picked),
            size: _size,
            radius: _size * K.avatarRadiusRatio,
          )
        else if (removing)
          SquircleAvatar(name: name, seed: server.id, size: _size)
        else
          ServerIcon(
            supabaseUrl: server.supabaseUrl,
            serverId: server.id,
            name: name,
            iconPath: server.iconPath,
            size: _size,
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppButton(
                    label: hasIcon ? 'Change icon' : 'Upload icon',
                    variant: AppButtonVariant.secondary,
                    onPressed: enabled ? onPick : null,
                  ),
                  if (hasIcon)
                    AppButton(
                      label: 'Remove',
                      variant: AppButtonVariant.secondary,
                      onPressed: enabled ? onRemove : null,
                    ),
                ],
              ),
              if (status != null)
                Text(
                  status,
                  style: AppText.label.copyWith(color: theme.textTertiary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
