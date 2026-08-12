import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/chat_quota.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../common/chat/chat_quota_meter.dart';

/// The central DM composer footer: [ChatQuotaMeter] wired to the central
/// cubit's daily budget, with the nudge that is specific to this tier — the
/// point of central's limit is to move a conversation that has become a real
/// one somewhere it isn't rationed.
class QuotaMeter extends StatelessWidget {
  const QuotaMeter({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CentralDmCubit>().state;
    return ChatQuotaMeter(
      quota: ChatQuota(
        quota: state.quota ?? ServerLimits.unlimited,
        remaining: state.remaining,
      ),
      nudge: 'move longer chats to a shared server',
      exhaustedNudge: 'continue on a server you share',
    );
  }
}
