import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/server/server_cubit.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../../logic/services/avatar_cache.dart';
import 'squircle_avatar.dart';

/// A member's picture, falling back to their initial.
///
/// Fetches lazily and only once per path: the cache is checked synchronously
/// first, so a already-loaded avatar renders on the first frame with no
/// flicker. Paths change on every upload, so a cache hit is never stale.
class UserAvatar extends StatefulWidget {
  final String? avatarPath;
  final String name;
  final double size;
  final ThemeState themeState;

  /// Stable id picking the fallback gradient. Pass a user id — falling back to
  /// the name means a rename changes someone's colour.
  final String? seed;

  const UserAvatar({
    super.key,
    required this.avatarPath,
    required this.name,
    required this.size,
    required this.themeState,
    this.seed,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarPath != widget.avatarPath) {
      _bytes = null;
      _resolve();
    }
  }

  void _resolve() {
    final path = widget.avatarPath;
    if (path == null) return;
    // Synchronous hit — avoids a frame of initials on every rebuild.
    final cached = AvatarCache.instance.get(path);
    if (cached != null) {
      _bytes = cached;
      return;
    }
    _load(path);
  }

  Future<void> _load(String path) async {
    final bytes = await context.read<ServerCubit>().loadAvatar(path);
    if (!mounted || bytes == null) return;
    // A slow fetch may land after the widget was pointed elsewhere.
    if (widget.avatarPath != path) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    // No picture yet → the same squircle-and-gradient everything else uses,
    // so a member with an avatar and one without still look like two members
    // rather than two different kinds of thing.
    if (bytes == null) {
      return SquircleAvatar(
        name: widget.name,
        seed: widget.seed,
        size: widget.size,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * K.avatarRadiusRatio),
      child: Image.memory(
        bytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}
