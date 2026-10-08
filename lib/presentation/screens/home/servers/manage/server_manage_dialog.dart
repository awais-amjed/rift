import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/reports/reports_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/hint_card.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/theme_context.dart';
import 'panels/bots_panel.dart';
import 'panels/danger_zone_panel.dart';
import 'panels/limits_panel.dart';
import 'panels/members_panel.dart';
import 'panels/overview_panel.dart';
import 'panels/reports_panel.dart';
import 'panels/roles_panel.dart';
import 'panels/soundboard_panel.dart';
import 'panels/voice_panel.dart';
import 'panels/webhooks_panel.dart';
import 'server_manage_tab.dart';
import 'widgets/manage_nav.dart';
import 'widgets/manage_panel.dart';

/// Everything about running [server], in one dialog with a page per concern.
///
/// There used to be a dialog for each — settings here, roles behind a shield
/// in the members list, bots and webhooks under each channel's right-click —
/// and finding any of them meant already knowing where it was. Now the rail's
/// menu opens this, on whichever page the caller had in mind, and the rest
/// are one click to the left.
///
/// It is for the people running the place. Leaving is a member's own business
/// and stays on the rail's menu; which pages exist beyond that is
/// [ServerManageTabs], and each page owns its own footer.
class ServerManageDialog extends StatefulWidget {
  final Server server;
  final ServerManageTab? initial;

  const ServerManageDialog({super.key, required this.server, this.initial});

  @override
  State<ServerManageDialog> createState() => _ServerManageDialogState();
}

class _ServerManageDialogState extends State<ServerManageDialog> {
  ServerManageTab? _active;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // Live, so a demotion while the dialog is open takes its pages away.
    final server =
        context.watch<ServerCubit>().state.serverById(widget.server.id) ??
        widget.server;
    final tabs = ServerManageTabs.visible(server.user?.permissions);
    if (tabs.isEmpty) {
      return AppModal(
        title: 'Manage server',
        subtitle: server.name,
        content: const HintCard(
          icon: Icons.visibility_outlined,
          text: 'Nothing here is yours to manage any more.',
        ),
      );
    }
    final active = tabs.contains(_active)
        ? _active!
        : tabs.contains(widget.initial)
        ? widget.initial!
        : tabs.first;

    if (context.layoutMode.isCompact) return _buildForPhone(server, tabs);

    return AppModal(
      title: 'Manage server',
      subtitle: server.name,
      maxWidth: K.manageDialogWidth,
      maxHeight: math.min(
        K.manageDialogHeight,
        MediaQuery.sizeOf(context).height * K.manageDialogHeightFraction,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ManageNav<ServerManageTab>(
            tabs: tabs,
            active: active,
            onSelected: (tab) => setState(() => _active = tab),
            labelOf: (tab) => tab.label,
            iconOf: (tab) => tab.icon,
            countOf: _countOf,
          ),
          VerticalDivider(width: 1, color: themeState.borderPrimary),
          Expanded(child: _page(active, server)),
        ],
      ),
    );
  }

  /// A phone: the pages as a list, and one page at a time with a way back.
  ///
  /// Only Members can be changed here — see [ManageReadOnly]. It is the page
  /// somebody running a server needs from wherever they are, when a member has
  /// to be muted or removed now.
  Widget _buildForPhone(Server server, List<ServerManageTab> tabs) {
    final open = tabs.contains(_active) ? _active : null;
    final themeState = context.theme;
    if (open == null) {
      // A page, like the pages it leads to. As a dialog it was a floating card
      // you tapped a row in to land on a full screen, and backing out of that
      // screen put you on a card again — one flow drawn two ways. No `onBack`,
      // so the chevron leaves Manage server: this is the first step, and there
      // is nothing behind it to go back to.
      return AppModal(
        title: 'Manage server',
        subtitle: server.name,
        pageOnPhone: true,
        body: SingleChildScrollView(
          child: ManageNav<ServerManageTab>(
            tabs: tabs,
            active: null,
            expand: true,
            onSelected: (tab) => setState(() => _active = tab),
            labelOf: (tab) => tab.label,
            iconOf: (tab) => tab.icon,
            countOf: _countOf,
          ),
        ),
      );
    }
    final page = _page(open, server);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _active = null);
      },
      // The headline is the page you are on, and "Manage server" steps down
      // to the line under it. It used to be the other way round, so the page
      // opened with two headlines — "Manage server / Rift Test" at the page
      // size, then the panel's own "Members / 3 members" under it — and four
      // lines of titling before anything you came for. [ManageHeadingAbove]
      // is what stops the panel drawing the second one.
      child: AppModal(
        title: open.label,
        subtitle: 'Manage server · ${server.name}',
        pageOnPhone: true,
        onBack: () => setState(() => _active = null),
        body: ColoredBox(
          color: themeState.bgSecondary,
          child: ManageHeadingAbove(
            child: open == ServerManageTab.members
                ? page
                // Reports are acted on from wherever a moderator is, which
                // is often a phone — the same reason Members is live here.
                : open == ServerManageTab.reports
                ? page
                : ManageReadOnly(child: page),
          ),
        ),
      ),
    );
  }

  /// Open reports, on the Reports row. Watched, so a report arriving while the
  /// dialog is open moves the badge.
  int _countOf(ServerManageTab tab) => tab == ServerManageTab.reports
      ? context.watch<ReportsCubit>().state.openCount
      : 0;

  Widget _page(ServerManageTab tab, Server server) => switch (tab) {
    ServerManageTab.overview => OverviewPanel(server: server),
    ServerManageTab.voice => VoicePanel(server: server),
    ServerManageTab.limits => LimitsPanel(server: server),
    ServerManageTab.roles => RolesPanel(serverId: server.id),
    ServerManageTab.members => MembersPanel(server: server),
    ServerManageTab.reports => const ReportsPanel(),
    ServerManageTab.bots => BotsPanel(server: server),
    ServerManageTab.webhooks => WebhooksPanel(server: server),
    ServerManageTab.soundboard => const SoundboardPanel(),
    ServerManageTab.danger => DangerZonePanel(server: server),
  };
}
