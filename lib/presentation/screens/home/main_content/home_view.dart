import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/enums/home_surface.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../chat/widgets/chat_header.dart';
import '../chat/widgets/header_pane_buttons.dart';
import '../dms/widgets/central_dm_list_panel.dart';
import '../sidebar/widgets/sidebar_content.dart';

/// What the content pane shows on a phone when nothing is open yet: the place
/// you have just navigated *to*.
///
/// On a desktop the sidebar is always there, so the pane can afford to say
/// "no channel selected" — the list you would pick from is a few pixels to the
/// left. On a phone it is a drawer, and that same emptiness was a dead end:
/// picking a server closed the drawer and left you looking at a sentence about
/// voice channels, with the only way onward being to reopen the drawer you had
/// just used. Choosing a server now takes you to the server.
///
/// It is the drawer's own list, not a second copy of it — the same
/// [ServerNavColumn] and [CentralDmListPanel], so there is one place where a
/// channel row is decided what it looks like and does.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (a, b) => a.surface != b.surface,
      builder: (context, appState) {
        return Column(
          children: [
            const _HomeBar(),
            Expanded(
              child: appState.surface == HomeSurface.centralDms
                  ? const CentralDmListPanel()
                  : const ServerNavColumn(inSidebar: false),
            ),
          ],
        );
      },
    );
  }
}

/// The bar the drawer button lives on.
///
/// Carries no title: both lists below name themselves — a server through its
/// own header, central DMs through theirs — and repeating that here would be
/// saying the same thing twice, a header's height apart.
class _HomeBar extends StatelessWidget {
  const _HomeBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      buildWhen: (a, b) => a.borderPrimary != b.borderPrimary,
      builder: (context, themeState) {
        return Container(
          height: ChatHeader.height,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
          ),
          child: const HeaderSidebarButton(),
        );
      },
    );
  }
}
