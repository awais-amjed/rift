import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/participant_info.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/app_sheet.dart';
import '../../../../../responsive/shell_scope.dart';
import 'verify_people_dialog.dart';

/// The encryption chip's press on a channel and in a call.
///
/// Both surfaces have more than one other person in them, so neither can open
/// a single safety code: they open the people instead, and each row leads to
/// its own code.

/// Everyone this client knows on the selected server, minus yourself and the
/// bots — a bot holds no chat key, and your own key is not yours to check.
List<VerifiablePerson> _knownPeople(BuildContext context) {
  final members = context.read<ServerMembersCubit>().state;
  final me = context.read<ServerCubit>().state.selectedServer?.user?.id;
  final people = [
    for (final member in members.byId.values)
      if (member.id != me && !member.isBot)
        VerifiablePerson(
          id: member.id,
          name: member.displayName,
          avatarPath: member.avatarPath,
          chatKey: member.chatPublicKey,
        ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return people;
}

/// Who can read a channel: every member holding a key it was wrapped to.
void showChannelEncryption(
  BuildContext context, {
  required String channelName,
}) {
  _show(
    context,
    subtitle: '#$channelName',
    explanation:
        'Messages here are sealed on your device to a key every member of '
        'this channel holds, and opened on theirs. The server stores them '
        'and cannot read them — but it is also what hands out the keys, so '
        'check the people you talk to.',
    people: _knownPeople(context),
  );
}

/// Who is in the call. A voice channel's audio is encrypted to the same
/// channel key its messages are, so the people are the same question.
void showCallEncryption(
  BuildContext context, {
  required String channelName,
  required List<ParticipantInfo> participants,
}) {
  final members = context.read<ServerMembersCubit>().state.byId;
  final me = context.read<ServerCubit>().state.selectedServer?.user?.id;
  final seen = <String>{};
  final people = <VerifiablePerson>[];
  for (final participant in participants) {
    // One row per person, not per connection: somebody on two devices is one
    // person with one key.
    if (participant.userId == me || !seen.add(participant.userId)) continue;
    final member = members[participant.userId];
    if (member?.isBot ?? false) continue;
    people.add(
      VerifiablePerson(
        id: participant.userId,
        name: member?.displayName ?? participant.name,
        avatarPath: member?.avatarPath,
        chatKey: member?.chatPublicKey,
      ),
    );
  }
  _show(
    context,
    subtitle: channelName,
    explanation:
        'Voice and video in this call are encrypted with the channel\'s own '
        'key, which every member holds and the server does not. Check the '
        'people you are in here with.',
    people: people,
  );
}

void _show(
  BuildContext context, {
  required String subtitle,
  required String explanation,
  required List<VerifiablePerson> people,
}) {
  final server = context.read<ServerCubit>().state.selectedServer;
  if (server == null) return;
  // Asked for now, while this context is alive: the roster resolves names for
  // anybody it has not paged in, and the dialog is a route of its own.
  context.read<ServerMembersCubit>().resolve([for (final p in people) p.id]);
  final dialog = MultiBlocProvider(
    providers: [
      BlocProvider.value(value: context.read<AppCubit>()),
      BlocProvider.value(value: context.read<VaultCubit>()),
    ],
    child: VerifyPeopleDialog(
      subtitle: subtitle,
      explanation: explanation,
      people: people,
      tier: 'server',
      myId: server.user?.id ?? '',
      host: Uri.parse(server.supabaseUrl).host,
    ),
  );
  if (context.layoutMode.isCompact) {
    showAppSheet<void>(context, dialog);
    return;
  }
  showCustomDialog<void>(context: context, builder: (_) => dialog);
}
