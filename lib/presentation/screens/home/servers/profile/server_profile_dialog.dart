import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../../data/classes/public_server.dart';
import '../../../../../data/classes/role.dart';
import '../../../../../data/classes/server.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/repositories/server_icon_repository.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/modal_columns.dart';
import '../../../../common/server_icon.dart';
import '../../../../common/viewable_picture.dart';
import '../../profile/person/widgets/profile_fact.dart';
import '../../profile/person/widgets/profile_facts.dart';
import '../../profile/person/widgets/profile_roles.dart';
import '../../profile/person/widgets/profile_section.dart';
import '../../profile/person/widgets/profile_skeleton_bar.dart';
import 'widgets/server_profile_about.dart';
import 'widgets/server_profile_actions.dart';
import 'widgets/server_profile_limits.dart';

/// A server's profile: what it is, who is here, what it allows, and the
/// doors to what you can do about it.
///
/// Written for a member first. Most people opening it want to know what
/// they have joined, and the admin's way in, Manage server, is one button
/// among the actions rather than the point of the page.
///
/// Built from what the app already holds about the server, its roster and
/// its limits, plus the one thing it does not: the description and tags of
/// its directory listing, asked of central when the profile opens and left
/// out when the server is not listed.
class ServerProfileDialog extends StatefulWidget {
  final String serverId;

  const ServerProfileDialog({super.key, required this.serverId});

  @override
  State<ServerProfileDialog> createState() => _ServerProfileDialogState();
}

class _ServerProfileDialogState extends State<ServerProfileDialog> {
  late final Future<PublicServer?> _listing;

  @override
  void initState() {
    super.initState();
    final server = context.read<ServerCubit>().state.serverOn(widget.serverId);
    _listing = server == null
        ? Future.value()
        : context.read<PublicServersCubit>().publicListing(
            supabaseUrl: server.supabaseUrl,
            serverId: server.id,
          );
    // Our own row, for when we joined and the roles we hold, which the
    // roster has not paged in on a server of any size.
    final me = server?.user?.id;
    if (me != null) context.read<ServerMembersCubit>().resolve([me]);
  }

  /// The narrowest a column may be before the two stack, as on a person's
  /// profile.
  static const double _columnWidth = 260;

  @override
  Widget build(BuildContext context) {
    final server = context.select<ServerCubit, Server?>(
      (c) => c.state.serverOn(widget.serverId),
    );
    // Left from here, or from another device, while it was open.
    if (server == null) return const SizedBox.shrink();

    return AppModal(
      title: server.name,
      subtitle: Uri.tryParse(server.supabaseUrl)?.host,
      titleIcon: ViewablePicture(
        origin: server.supabaseUrl,
        // Only an icon `ServerIcon` would fetch and draw.
        path: ServerIconRepository.isIconOf(server.id, server.iconPath)
            ? server.iconPath
            : null,
        name: server.name,
        child: ServerIcon.of(server, size: _iconSize),
      ),
      maxWidth: K.profileWidth,
      sheetOnPhone: true,
      content: ModalColumns(
        minColumnWidth: _columnWidth,
        children: [
          _identity(server),
          ServerProfileActions(server: server),
        ],
      ),
    );
  }

  /// The size of a person's picture at the head of their profile.
  static const double _iconSize = 56;

  /// What the server is: its listing, the people in it, our place there,
  /// and its limits.
  Widget _identity(Server server) {
    final members = context.watch<ServerMembersCubit>().state;
    final me = server.user?.id;
    final roles = members.memberRoles[me] ?? const <Role>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FutureBuilder<PublicServer?>(
          future: _listing,
          builder: (_, snapshot) => switch (snapshot.data) {
            final listing? => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: ServerProfileAbout(listing: listing),
            ),
            null => const SizedBox.shrink(),
          },
        ),
        ProfileSection(
          label: 'Server',
          spaced: false,
          child: members.loaded
              ? ProfileFacts(facts: _facts(server, members))
              : const ProfileSkeletonBar(widthFactor: 0.52),
        ),
        ProfileSection(
          label: 'Your roles',
          child: members.byId[me] == null
              ? const ProfileSkeletonBar(widthFactor: 0.34, height: 15)
              : ProfileRoles(roles: roles),
        ),
        ServerProfileLimits(server: server),
      ],
    );
  }

  List<ProfileFact> _facts(Server server, ServerMembersState members) {
    final number = NumberFormat.decimalPattern();
    final presence = context.watch<ChannelPresenceCubit>().state;
    final joined = members.byId[server.user?.id]?.joinedAt;
    return [
      ProfileFact(label: 'People', value: number.format(members.peopleCount)),
      if (presence.onlineKnown)
        ProfileFact(
          label: 'Online',
          value: number.format(presence.onlineUserIds.length),
        ),
      if (members.bots.isNotEmpty)
        ProfileFact(label: 'Bots', value: number.format(members.bots.length)),
      if (joined != null)
        ProfileFact(
          label: 'You joined',
          value: DateFormat('d MMMM y').format(joined.toLocal()),
        ),
    ];
  }
}
