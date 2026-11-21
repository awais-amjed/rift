import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift_crypto/rift_crypto.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/repositories/session_repository.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../logic/services/forwarding/forward_service.dart';
import '../../../../logic/services/forwarding/forward_targets.dart';
import '../../app_modal.dart';
import 'forward_dialog.dart';

/// Open the forward picker for [message].
///
/// Gathers the destinations from the cubits already in scope rather than
/// making each chat view do it: the three views would otherwise each have
/// their own idea of what counts as somewhere you can send a message, and
/// the one that got it wrong would be the one nobody opened.
///
/// [sourceServerId] is where the message's attachment blobs live — null
/// means central. It is used to *fetch* the bytes and is never written into
/// the message: nothing about where a forward came from travels with it.
Future<void> showForwardDialog(
  BuildContext context, {
  required ChatMessage message,
  String? sourceServerId,
  String? currentChannelId,
  String? currentPeerId,
}) {
  final servers = context.read<ServerCubit>();
  final session = context.read<SessionRepository>();
  final vault = context.read<VaultCubit>();
  final dms = context.read<DmCubit>();
  final central = context.read<CentralDmCubit>();
  final themeCubit = context.read<ThemeCubit>();
  final app = context.read<AppCubit>();

  // A forward seals to each person's key as the list has it, and only a
  // change already noticed held them back: one never seen, because their
  // conversation had not been opened since, was sealed to without a word
  // (review, Nov 22). So the keys listed for people this device verified
  // are noted first, as opening their conversation would, and a changed one
  // holds them here too.
  for (final (tier, conversations) in [
    ('server', dms.state.conversations),
    ('central', central.state.conversations),
  ]) {
    for (final conversation in conversations) {
      final person = '$tier:${conversation.peerId}';
      final key = conversation.peerChatPublicKey;
      if (key == null || key.isEmpty) continue;
      if (!app.state.verifiedCodes.containsKey(person)) continue;
      app.noteChatKey(person, key);
    }
  }

  final targets = ForwardTargets.gather(
    servers: servers.state.servers,
    serverDms: dms.state.conversations,
    // Server DMs are loaded for one server only, so those are the ones that
    // can be offered. Naming the host here rather than guessing inside the
    // gatherer keeps that limit visible.
    serverDmHost: servers.state.serverOn(dms.serverId),
    centralDms: central.state.conversations,
    currentChannelId: currentChannelId,
    currentPeerId: currentPeerId,
    held: app.state.keysToCheck,
  );

  return showCustomDialog(
    context: context,
    build: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: themeCubit),
        BlocProvider.value(value: servers),
      ],
      child: ForwardDialog(
        message: message,
        targets: targets,
        sourceServerId: sourceServerId,
        service: ForwardService(
          session: session,
          vault: vault,
          crypto: CryptoRepository(),
        ),
      ),
    ),
  );
}
