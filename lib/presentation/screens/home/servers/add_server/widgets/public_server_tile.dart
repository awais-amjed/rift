import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/public_server.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/squircle_avatar.dart';
import '../../../../../theme/app_text.dart';

/// One server in the browser.
///
/// The host is shown next to the member count because it is the only piece of
/// provenance a stranger has: a listing is written by whoever published it, and
/// central verifies none of it. Where the server actually lives is the one
/// thing on the row that can't be made up.
class PublicServerTile extends StatelessWidget {
  final PublicServer server;

  /// Null when this client is already a member — the row says so instead of
  /// offering a second registration that would fail on the username.
  final VoidCallback? onJoin;

  const PublicServerTile({super.key, required this.server, this.onJoin});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: themeState.bgHover,
            borderRadius: BorderRadius.circular(K.radiusCard),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              SquircleAvatar(
                name: server.name,
                seed: server.serverId,
                imageUrl: server.iconUrl,
                size: 40,
              ),
              Expanded(child: _details(themeState)),
              if (onJoin != null)
                AppButton(label: 'Join', onPressed: onJoin)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    'Joined',
                    style: AppText.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: themeState.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _details(ThemeState themeState) {
    final description = server.description;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          server.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.row.copyWith(color: themeState.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          '${server.memberCount} '
          '${server.memberCount == 1 ? 'member' : 'members'} · ${server.host}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.label.copyWith(
            fontWeight: FontWeight.w400,
            color: themeState.textTertiary,
          ),
        ),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.secondary.copyWith(color: themeState.textSecondary),
          ),
        ],
        if (server.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final tag in server.tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: themeState.bgTertiary,
                    borderRadius: BorderRadius.circular(K.radiusPill),
                  ),
                  child: Text(
                    tag,
                    style: AppText.label.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
