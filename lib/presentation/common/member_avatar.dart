import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/server_members/server_members_cubit.dart';
import 'user_avatar.dart';

/// A server member's picture, read from the live roster.
///
/// The roster is refreshed whenever a member's row changes, so a new picture
/// reaches everyone at once. The voice list and the call's tiles used to draw
/// the initial alone, and chat rows the picture as it was when they loaded, so
/// a new picture showed up in the member list and nowhere else.
class MemberAvatar extends StatelessWidget {
  final String userId;
  final String name;
  final double size;

  /// The picture as whoever built this row last saw it, for somebody the
  /// roster has not resolved yet — see [ServerMembersState.avatarFor].
  final String? fallbackPath;

  const MemberAvatar({
    super.key,
    required this.userId,
    required this.name,
    required this.size,
    this.fallbackPath,
  });

  @override
  Widget build(BuildContext context) {
    final path = context.select<ServerMembersCubit, String?>(
      (cubit) => cubit.state.avatarFor(userId, fallbackPath),
    );
    return UserAvatar(avatarPath: path, name: name, seed: userId, size: size);
  }
}
