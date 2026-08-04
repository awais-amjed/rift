import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/enums/home_surface.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/nav_row.dart';
import '../../../../common/unread_badge.dart';

/// The way into this server's DMs, above its channels.
///
/// It sits in the server column rather than on the rail because that is what
/// scopes it: these conversations belong to this server and change when you
/// switch. The rail's Home entry is the other tier — your account's DMs,
/// which follow you everywhere.
class ServerDmsRow extends StatelessWidget {
  const ServerDmsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (a, b) => a.surface != b.surface,
      builder: (context, appState) {
        return BlocBuilder<DmCubit, DmState>(
          buildWhen: (a, b) => a.conversations != b.conversations,
          builder: (context, dmState) {
            final count = dmState.conversations.length;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: NavRow(
                icon: Icons.forum_outlined,
                label: 'Server DMs',
                isSelected: appState.surface == HomeSurface.serverDms,
                // A tally of open threads, not unread news — so it takes the
                // tinted badge rather than the solid one the channels use.
                trailing: count > 0
                    ? UnreadBadge(
                        count: count,
                        themeState: context.watch<ThemeCubit>().state,
                        quiet: true,
                      )
                    : null,
                onTap: () =>
                    context.read<AppCubit>().setSurface(HomeSurface.serverDms),
              ),
            );
          },
        );
      },
    );
  }
}
