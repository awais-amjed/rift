import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/hint_card.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/theme_context.dart';
import '../../servers/manage/widgets/manage_nav.dart';
import '../../servers/manage/widgets/manage_panel.dart';
import '../bots/channel_bots_panel.dart';
import '../bots/voice_bots_panel.dart';
import 'channel_settings_tab.dart';
import 'panels/channel_access_panel.dart';
import 'panels/channel_delete_panel.dart';
import 'panels/channel_overview_panel.dart';
import 'panels/channel_webhooks_panel.dart';

/// Everything about one channel, a page per concern — Manage server's shape,
/// for a channel.
///
/// These used to be five dialogs off the channel's right-click menu (settings,
/// who can see it, making it private, bots, webhooks), found only by somebody
/// who already knew to right-click. Now the row's gear and the menu both open
/// this, and the rest is one click to the left.
///
/// Reads the channel live, so a rename shows in the header, going private
/// swaps the Access page, and a channel deleted from here or elsewhere closes
/// the dialog rather than leaving it editing nothing.
class ChannelSettingsDialog extends StatefulWidget {
  final Channel channel;
  final ChannelSettingsTab? initial;

  const ChannelSettingsDialog({super.key, required this.channel, this.initial});

  @override
  State<ChannelSettingsDialog> createState() => _ChannelSettingsDialogState();
}

class _ChannelSettingsDialogState extends State<ChannelSettingsDialog> {
  ChannelSettingsTab? _active;
  bool _closing = false;

  /// Gone from the server — deleted here, or by somebody else meanwhile.
  void _closeOnce() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final channel = context.select<ServerCubit, Channel?>(
      (c) => c.state.selectedServer?.channels
          .where((ch) => ch.id == widget.channel.id)
          .firstOrNull,
    );
    if (channel == null) {
      _closeOnce();
      return const SizedBox.shrink();
    }

    final canManage = canManageChannel(context, channel);
    final tabs = visibleChannelSettingsTabs(channel, canManage: canManage);
    final title = canManage ? 'Channel settings' : 'Who can see this';
    final subtitle = channel.hasMessages ? '#${channel.name}' : channel.name;

    if (tabs.isEmpty) {
      return AppModal(
        title: title,
        subtitle: subtitle,
        content: const HintCard(
          icon: Icons.visibility_outlined,
          text: 'Nothing here is yours to change any more.',
        ),
      );
    }
    final active = tabs.contains(_active)
        ? _active!
        : tabs.contains(widget.initial)
        ? widget.initial!
        : tabs.first;

    if (context.layoutMode.isCompact) {
      return _buildForPhone(channel, tabs, canManage, title, subtitle);
    }

    final themeState = context.theme;
    final page = _page(active, channel, canManage);
    return AppModal(
      title: title,
      subtitle: subtitle,
      // One page is a small dialog about that page, not a frame with a nav
      // column listing nothing else.
      maxWidth: tabs.length == 1 ? K.dialogWidth : K.channelSettingsWidth,
      maxHeight: math.min(
        K.channelSettingsHeight,
        MediaQuery.sizeOf(context).height * K.manageDialogHeightFraction,
      ),
      // Alone, the page's own heading would repeat the dialog's title.
      body: tabs.length == 1
          ? ColoredBox(
              color: themeState.bgSecondary,
              child: ManageHeadingAbove(child: page),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ManageNav<ChannelSettingsTab>(
                  tabs: tabs,
                  active: active,
                  onSelected: (tab) => setState(() => _active = tab),
                  labelOf: (tab) => tab.label,
                  iconOf: (tab) => tab.icon,
                ),
                VerticalDivider(width: 1, color: themeState.borderPrimary),
                Expanded(child: page),
              ],
            ),
    );
  }

  /// A phone: the pages as a list, and one page at a time with a way back —
  /// Manage server's phone shape. Every page stays editable: each is one
  /// short form or list, not the permission grids that made Manage server's
  /// read-only there.
  Widget _buildForPhone(
    Channel channel,
    List<ChannelSettingsTab> tabs,
    bool canManage,
    String title,
    String subtitle,
  ) {
    final themeState = context.theme;
    final open = tabs.length == 1
        ? tabs.single
        : tabs.contains(_active)
        ? _active
        : null;
    if (open == null) {
      return AppModal(
        title: title,
        subtitle: subtitle,
        pageOnPhone: true,
        body: SingleChildScrollView(
          child: ManageNav<ChannelSettingsTab>(
            tabs: tabs,
            active: null,
            expand: true,
            onSelected: (tab) => setState(() => _active = tab),
            labelOf: (tab) => tab.label,
            iconOf: (tab) => tab.icon,
          ),
        ),
      );
    }
    final body = AppModal(
      title: tabs.length == 1 ? title : open.label,
      subtitle: tabs.length == 1 ? subtitle : '$title · $subtitle',
      pageOnPhone: true,
      onBack: tabs.length == 1 ? null : () => setState(() => _active = null),
      body: ColoredBox(
        color: themeState.bgSecondary,
        child: ManageHeadingAbove(child: _page(open, channel, canManage)),
      ),
    );
    if (tabs.length == 1) return body;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _active = null);
      },
      child: body,
    );
  }

  Widget _page(ChannelSettingsTab tab, Channel channel, bool canManage) =>
      switch (tab) {
        ChannelSettingsTab.overview => ChannelOverviewPanel(
          key: ValueKey('overview-${channel.id}'),
          channel: channel,
        ),
        // Keyed on privacy, so opening or closing the room starts the page
        // over for what it now is.
        ChannelSettingsTab.access => ChannelAccessPanel(
          key: ValueKey('access-${channel.id}-${channel.isPrivate}'),
          channel: channel,
          canManage: canManage,
        ),
        ChannelSettingsTab.bots =>
          channel.hasMessages
              ? ChannelBotsPanel(channel: channel)
              : VoiceBotsPanel(channel: channel),
        ChannelSettingsTab.webhooks => ChannelWebhooksPanel(channel: channel),
        ChannelSettingsTab.delete => ChannelDeletePanel(channel: channel),
      };
}
