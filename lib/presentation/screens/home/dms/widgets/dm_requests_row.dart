import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../common/nav_row.dart';
import '../../../../common/unread_badge.dart';
import '../dm_requests_dialog.dart';

/// The way in to message requests, and to who may send them, at the top of
/// the server's DM list.
///
/// Always there rather than only when something is waiting: it is also where
/// the setting lives, and a setting that appears only once somebody has
/// already used it is one nobody finds in time.
class DmRequestsRow extends StatelessWidget {
  const DmRequestsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.select<DmCubit, int>((c) => c.state.requests.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: NavRow(
        icon: Icons.mark_email_unread_outlined,
        label: 'Message requests',
        isUnread: count > 0,
        trailing: count > 0 ? UnreadBadge(count: count) : null,
        pushes: true,
        onTap: () => unawaited(showDmRequestsDialog(context)),
      ),
    );
  }
}
