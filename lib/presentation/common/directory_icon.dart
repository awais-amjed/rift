import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../../data/repositories/directory_icon_repository.dart';
import '../../logic/services/avatar_cache.dart';
import 'squircle_avatar.dart';

/// A directory listing's picture, falling back to its initial.
///
/// The same shape as [UserAvatar] and for the same reasons — fetch lazily,
/// once per path, cache hit checked synchronously so an icon already loaded
/// renders on the first frame. What differs is only where the bytes come
/// from: central's private `directory-icons` bucket rather than a server's.
///
/// It is deliberately *not* a [CachedNetworkImage] on a remote address, which
/// is what this replaced: that handed every listed party the address of
/// everyone who opened the browser. See [DirectoryIconRepository].
class DirectoryIcon extends StatefulWidget {
  /// Object path in the `directory-icons` bucket, or null for no picture.
  final String? iconPath;

  /// Supplies the initial and the fallback gradient.
  final String name;
  final double size;

  /// Stable id picking the gradient, so a rename does not recolour a listing.
  final String? seed;

  const DirectoryIcon({
    super.key,
    required this.iconPath,
    required this.name,
    required this.size,
    this.seed,
  });

  @override
  State<DirectoryIcon> createState() => _DirectoryIconState();
}

class _DirectoryIconState extends State<DirectoryIcon> {
  static final DirectoryIconRepository _icons = DirectoryIconRepository();

  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(DirectoryIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iconPath != widget.iconPath) {
      _bytes = null;
      _resolve();
    }
  }

  void _resolve() {
    final path = widget.iconPath;
    if (path == null) return;
    final cached = AvatarCache.instance.get(path);
    if (cached != null) {
      _bytes = cached;
      return;
    }
    _load(path);
  }

  Future<void> _load(String path) async {
    final bytes = await _icons.download(path);
    if (!mounted || bytes == null) return;
    // A slow fetch may land after the tile was recycled onto another listing.
    if (widget.iconPath != path) return;
    AvatarCache.instance.put(path, bytes);
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
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
