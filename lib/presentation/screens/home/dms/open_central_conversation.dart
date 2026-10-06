import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/dm_conversation.dart';
import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';

/// Open one central conversation, from wherever the person was picked.
///
/// Four places lead here now — the conversation list, the requests section,
/// the handle search, the friends page — and every one of them has to do the
/// same two things: close the *server* DM first, because only one DM surface
/// is open at a time, and hand over the peer's published keys so the
/// conversation can derive its key without a second directory round trip.
///
/// It was copied into each of them until the fourth wanted it. Forgetting the
/// first line is a bug you only see as two conversations open at once. The
/// server DM is set aside rather than just closed, so going back to the
/// server's DMs finds it open again.
void openCentralConversation(
  BuildContext context,
  DmConversation conversation,
) {
  context.read<DmCubit>().setAsideConversation();
  context.read<CentralDmCubit>().openConversation(
    peerId: conversation.peerId,
    peerHandle: conversation.peerName,
    peerChatKey: conversation.peerChatPublicKey,
    peerSigningKey: conversation.peerSigningPublicKey,
  );
}
