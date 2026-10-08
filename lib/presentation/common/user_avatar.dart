import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/media/media_cubit.dart';
import '../../logic/cubits/server/server_cubit.dart';
import 'stored_picture.dart';

/// A member's picture, falling back to their initial.
///
/// Asks [MediaCubit] for the picture and draws whatever it holds, so every
/// avatar of the same person shows the same thing: one already fetched draws
/// on the first frame, and one that lands later reaches all of them at once.
/// Paths change on every upload, so a held picture is never stale.
class UserAvatar extends StatefulWidget {
  final String? avatarPath;
  final String name;
  final double size;

  /// Stable id picking the fallback gradient. Pass a user id — falling back to
  /// the name means a rename changes someone's colour.
  final String? seed;

  const UserAvatar({
    super.key,
    required this.avatarPath,
    required this.name,
    required this.size,
    this.seed,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  @override
  void initState() {
    super.initState();
    _want();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarPath != widget.avatarPath) _want();
  }

  void _want() {
    final path = widget.avatarPath;
    if (path == null) return;
    final server = context.read<ServerCubit>();
    context.read<MediaCubit>().want(
      MediaKind.image,
      path,
      () => server.loadAvatar(path),
    );
  }

  @override
  Widget build(BuildContext context) => StoredPicture(
    path: widget.avatarPath,
    name: widget.name,
    seed: widget.seed,
    size: widget.size,
  );
}
