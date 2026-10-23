import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/classes/server.dart';
import '../../data/repositories/server_icon_repository.dart';
import '../../logic/cubits/media/media_cubit.dart';
import 'stored_picture.dart';

/// A server's icon, falling back to its initial.
///
/// The same shape as [UserAvatar] and [DirectoryIcon]: it asks [MediaCubit]
/// and draws what it holds, so the rail, the sidebar header and the switcher
/// all show one copy. The bytes come from the server's own public `servers`
/// bucket, and only for a path in that server's folder
/// ([ServerIconRepository.isIconOf]); anything else draws the initial.
class ServerIcon extends StatefulWidget {
  /// The project the icon is stored on.
  final String supabaseUrl;

  /// The server, which seeds the fallback gradient and names the one folder
  /// an icon may come from.
  final String serverId;

  /// Supplies the initial.
  final String name;

  /// Object path in the `servers` bucket, or null for no picture.
  final String? iconPath;

  final double size;

  /// Corner radius; defaults to the avatar's, size/3.
  final double? radius;

  const ServerIcon({
    super.key,
    required this.supabaseUrl,
    required this.serverId,
    required this.name,
    required this.iconPath,
    required this.size,
    this.radius,
  });

  /// The icon of [server].
  ServerIcon.of(Server server, {Key? key, required double size, double? radius})
    : this(
        key: key,
        supabaseUrl: server.supabaseUrl,
        serverId: server.id,
        name: server.name,
        iconPath: server.iconPath,
        size: size,
        radius: radius,
      );

  @override
  State<ServerIcon> createState() => _ServerIconState();
}

class _ServerIconState extends State<ServerIcon> {
  String? get _path =>
      ServerIconRepository.isIconOf(widget.serverId, widget.iconPath)
      ? widget.iconPath
      : null;

  @override
  void initState() {
    super.initState();
    _want();
  }

  @override
  void didUpdateWidget(ServerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iconPath != widget.iconPath ||
        oldWidget.supabaseUrl != widget.supabaseUrl) {
      _want();
    }
  }

  void _want() {
    final path = _path;
    if (path == null) return;
    context.read<MediaCubit>().wantServerIcon(widget.supabaseUrl, path);
  }

  @override
  Widget build(BuildContext context) => StoredPicture(
    origin: widget.supabaseUrl,
    path: _path,
    name: widget.name,
    seed: widget.serverId,
    size: widget.size,
    radius: widget.radius,
  );
}
