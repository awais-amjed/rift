import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';

import '../../../../data/classes/chat_message.dart';
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
/// means central. [source] is the line written into the forwarded block,
/// which is the forwarder's own account of where it came from.
Future<void> showForwardDialog(
  BuildContext context, {
  required ChatMessage message,
  String? source,
  String? sourceServerId,
  String? currentChannelId,
  String? currentPeerId,
}) {
  final servers = context.read<ServerCubit>();
  final vault = context.read<VaultCubit>();
  final dms = context.read<DmCubit>();
  final central = context.read<CentralDmCubit>();
  final themeCubit = context.read<ThemeCubit>();

  final targets = ForwardTargets.gather(
    servers: servers.state.servers,
    serverDms: dms.state.conversations,
    // Server DMs are loaded for the open server only, so those are the ones
    // that can be offered. Naming the host here rather than guessing inside
    // the gatherer keeps that limit visible.
    serverDmHost: servers.state.selectedServer,
    centralDms: central.state.conversations,
    currentChannelId: currentChannelId,
    currentPeerId: currentPeerId,
  );

  return showCustomDialog(
    context: context,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: themeCubit),
        BlocProvider.value(value: servers),
      ],
      child: ForwardDialog(
        message: message,
        targets: targets,
        source: source,
        sourceServerId: sourceServerId,
        service: ForwardService(
          servers: servers,
          vault: vault,
          crypto: CryptoRepository(),
        ),
      ),
    ),
  );
}
