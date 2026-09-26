import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../theme/theme_context.dart';
import '../../app_modal.dart';
import '../../empty_state.dart';
import '../../loading_block.dart';
import '../../popover_surface.dart';
import 'pinned_message_tile.dart';
import 'pinned_messages_header.dart';

/// The messages a conversation keeps at hand, newest pin first.
///
/// Shared by channels, server DMs and central DMs — each surface hands in how
/// to read its pins, how to take one down, and where pressing one goes. The
/// list is read when this opens rather than held by a cubit: pins change
/// rarely, and a list nobody is looking at is not worth keeping current.
///
/// Two frames around one list: a panel hanging from the header's pin button
/// on a desktop, where the conversation stays in view beside it, and a page
/// on a phone, where there is no beside.
class PinnedMessagesPanel extends StatefulWidget {
  /// The pinned messages, decrypted, or null when they could not be read.
  final Future<List<ChatMessage>?> Function() load;

  /// Go to [message] in the conversation. The panel closes first.
  final void Function(ChatMessage message)? onJump;

  /// Take the pin off [message]; answers whether it worked. Null where the
  /// reader may not unpin.
  final Future<bool> Function(ChatMessage message)? onUnpin;

  /// `@username` → display name, for mentions in the pinned text.
  final Map<String, String> displayNames;

  /// A phone page rather than a panel.
  final bool asPage;

  const PinnedMessagesPanel({
    super.key,
    required this.load,
    this.onJump,
    this.onUnpin,
    this.displayNames = const {},
    this.asPage = false,
  });

  /// Wide enough for a message to read as one; narrower than the chat, so
  /// the conversation it came from stays visible beside it.
  static const double width = 440;

  @override
  State<PinnedMessagesPanel> createState() => _PinnedMessagesPanelState();
}

class _PinnedMessagesPanelState extends State<PinnedMessagesPanel> {
  List<ChatMessage>? _pins;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pins = await widget.load();
    if (!mounted) return;
    setState(() {
      _pins = pins;
      _failed = pins == null;
      _loading = false;
    });
  }

  Future<void> _unpin(ChatMessage message) async {
    final unpin = widget.onUnpin;
    if (unpin == null) return;
    if (!await unpin(message) || !mounted) return;
    setState(() => _pins = [...?_pins]..removeWhere((m) => m.id == message.id));
  }

  void _jump(ChatMessage message) {
    Navigator.of(context).pop();
    widget.onJump?.call(message);
  }

  int? get _count => _loading || _failed ? null : (_pins ?? const []).length;

  @override
  Widget build(BuildContext context) {
    if (widget.asPage) {
      return AppModal(
        title: 'Pinned messages',
        count: _count,
        pageOnPhone: true,
        maxWidth: PinnedMessagesPanel.width,
        body: _body(context),
      );
    }
    final themeState = context.theme;
    return PopoverSurface(
      child: ClipRRect(
        // One inside the surface's radius, so a hovered row stops short of
        // the ring instead of painting over its corners.
        borderRadius: BorderRadius.circular(PopoverSurface.radius - 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PinnedMessagesHeader(count: _count),
            Divider(height: 1, thickness: 1, color: themeState.borderElevated),
            Flexible(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const LoadingBlock(height: 160);
    if (_failed) {
      return const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn’t load the pins',
        message: 'Close this and try again in a moment.',
      );
    }
    final pins = _pins ?? const [];
    if (pins.isEmpty) {
      return const EmptyState(
        icon: Icons.push_pin_outlined,
        title: 'Nothing pinned yet',
        message:
            'Pin a message from its menu to keep it here, where anyone in '
            'the conversation can find it.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.all(6),
      itemCount: pins.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, i) {
        final message = pins[i];
        return PinnedMessageTile(
          key: ValueKey(message.id),
          message: message,
          displayNames: widget.displayNames,
          onJump: widget.onJump == null ? null : () => _jump(message),
          onUnpin: widget.onUnpin == null ? null : () => _unpin(message),
        );
      },
    );
  }
}
