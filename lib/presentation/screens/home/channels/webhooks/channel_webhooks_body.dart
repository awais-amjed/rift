import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/classes/webhook.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../common/message_banner.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'widgets/webhook_create_row.dart';
import 'widgets/webhook_list.dart';
import 'widgets/webhook_secret_card.dart';

/// Manage the webhooks that post into one channel (BOTS.md §7).
///
/// A webhook is the only way something with no Rift identity can put a message
/// in a channel, so this says plainly what that costs: these messages are not
/// encrypted, and they are badged in the channel to match.
///
/// The body only — it is the same list whether it opens from a channel's menu
/// ([ChannelWebhooksDialog]) or on the webhooks page of the manage-server
/// dialog, which puts a channel picker above it.
class ChannelWebhooksBody extends StatefulWidget {
  final Channel channel;

  const ChannelWebhooksBody({super.key, required this.channel});

  @override
  State<ChannelWebhooksBody> createState() => _ChannelWebhooksBodyState();
}

class _ChannelWebhooksBodyState extends State<ChannelWebhooksBody> {
  final TextEditingController _nameCtrl = TextEditingController();

  List<Webhook> _webhooks = const [];
  bool _isLoading = true;
  bool _isCreating = false;
  String? _error;

  /// The URL of the one just minted, held only until this dialog closes.
  WebhookSecret? _created;
  bool _copied = false;

  String get _name => _nameCtrl.text.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await context.read<ServerCubit>().listWebhooks(
      widget.channel.id,
    );
    if (!mounted) return;
    setState(() {
      _webhooks = result.webhooks;
      _error = result.error;
      _isLoading = false;
    });
  }

  Future<void> _create() async {
    if (_name.isEmpty || _isCreating) return;
    setState(() {
      _isCreating = true;
      _error = null;
      _created = null;
    });

    final result = await context.read<ServerCubit>().createWebhook(
      channelId: widget.channel.id,
      name: _name,
    );
    if (!mounted) return;

    setState(() {
      _isCreating = false;
      _created = result.created;
      _error = result.error;
      if (result.created != null) {
        _nameCtrl.clear();
        _copied = false;
      }
    });
    if (result.created != null) await _load();
  }

  Future<void> _delete(Webhook webhook) async {
    final serverCubit = context.read<ServerCubit>();
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Revoke ${webhook.name}?',
      message:
          'Anything posting to its URL stops working immediately. Messages it '
          'already posted stay in the channel.',
      confirmLabel: 'Revoke',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (!confirmed) return;

    final result = await serverCubit.deleteWebhook(webhook.id);
    if (!mounted) return;
    // The card is for the webhook that was just minted; revoking anything
    // afterwards makes it stale, and a URL on screen that may be the one just
    // revoked is worse than no URL.
    setState(() {
      _error = result.error;
      _created = null;
    });
    await _load();
  }

  Future<void> _copy() async {
    final url = _created?.url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        Text(
          'A webhook lets an outside service — a build, an alert, a script — '
          'post here without an account. Those messages are not encrypted and '
          'are labelled in the channel to say so.',
          style: AppText.meta.copyWith(color: themeState.textSecondary),
        ),
        if (_error != null)
          MessageBanner(message: _error!, kind: MessageBannerKind.error),
        if (_created != null)
          WebhookSecretCard(created: _created!, copied: _copied, onCopy: _copy),
        WebhookCreateRow(
          controller: _nameCtrl,
          isBusy: _isCreating,
          onChanged: (_) => setState(() {}),
          onCreate: _name.isEmpty || _isCreating ? null : _create,
        ),
        WebhookList(
          webhooks: _webhooks,
          isLoading: _isLoading,

          onDelete: _delete,
        ),
      ],
    );
  }
}
