import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../../../../data/classes/server.dart';
import 'initial_avatar.dart';

/// Server avatar that shows icon or initial fallback.
class ServerAvatar extends StatelessWidget {
  final Server server;

  const ServerAvatar({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    if (server.iconUrl != null && server.iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9999),
        child: CachedNetworkImage(
          imageUrl: server.iconUrl!,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => InitialAvatar(name: server.name),
        ),
      );
    }
    return InitialAvatar(name: server.name);
  }
}
