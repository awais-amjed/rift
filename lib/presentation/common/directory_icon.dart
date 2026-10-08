import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/directory_icon_repository.dart';
import '../../logic/cubits/media/media_cubit.dart';
import 'stored_picture.dart';

/// A directory listing's picture, falling back to its initial.
///
/// The same shape as [UserAvatar] and for the same reasons: it asks
/// [MediaCubit] and draws what it holds. What differs is only where the bytes
/// come from: central's private `directory-icons` bucket rather than a
/// server's.
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
  @override
  void initState() {
    super.initState();
    _want();
  }

  @override
  void didUpdateWidget(DirectoryIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iconPath != widget.iconPath) _want();
  }

  void _want() {
    final path = widget.iconPath;
    if (path != null) context.read<MediaCubit>().wantDirectoryIcon(path);
  }

  @override
  Widget build(BuildContext context) => StoredPicture(
    path: widget.iconPath,
    name: widget.name,
    seed: widget.seed,
    size: widget.size,
  );
}
