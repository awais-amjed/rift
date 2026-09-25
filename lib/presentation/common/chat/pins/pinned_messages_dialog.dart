import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../theme/theme_context.dart';
import '../../app_modal.dart';
import '../../empty_state.dart';
import '../../loading_block.dart';
import 'pinned_message_tile.dart';

/// The messages a conversation keeps at hand, newest pin first.
///
/// Shared by channels, server DMs and central DMs — each surface hands in how
/// to read its pins, how to take one down, and where pressing one goes. The
/// list is read when this opens rather than held by a cubit: pins change
/// rarely, and a list nobody is looking at is not worth keeping current.
class PinnedMessagesDialog extends StatefulWidget {
  /// The pinned messages, decrypted, or null when they could not be read.
  final Future<List<ChatMessage>?> Function() load;

  /// Go to [message] in the conversation. The dialog closes first.
  final void Function(ChatMessage message)? onJump;

  /// Take the pin off [message]; answers whether it worked. Null where the
  /// reader may not unpin.
  final Future<bool> Function(ChatMessage message)? onUnpin;

  const PinnedMessagesDialog({
    super.key,
    required this.load,
    this.onJump,
    this.onUnpin,
  });

  @override
  State<PinnedMessagesDialog> createState() => _PinnedMessagesDialogState();
}

class _PinnedMessagesDialogState extends State<PinnedMessagesDialog> {
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

  @override
  Widget build(BuildContext context) {
    final pins = _pins ?? const [];
    return AppModal(
      title: 'Pinned messages',
      count: _loading || _failed ? null : pins.length,
      pageOnPhone: true,
      maxWidth: 520,
      body: _body(context, pins),
    );
  }

  Widget _body(BuildContext context, List<ChatMessage> pins) {
    if (_loading) return const LoadingBlock(height: 160);
    if (_failed) {
      return const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn’t load the pins',
        message: 'Close this and try again in a moment.',
      );
    }
    if (pins.isEmpty) {
      return const EmptyState(
        icon: Icons.push_pin_outlined,
        title: 'Nothing pinned yet',
        message:
            'Pin a message from its menu to keep it here, where anyone in '
            'the conversation can find it.',
      );
    }
    return ColoredBox(
      color: context.theme.bgElevated,
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        itemCount: pins.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final message = pins[i];
          return PinnedMessageTile(
            key: ValueKey(message.id),
            message: message,
            onJump: widget.onJump == null ? null : () => _jump(message),
            onUnpin: widget.onUnpin == null ? null : () => _unpin(message),
          );
        },
      ),
    );
  }
}

/// Open the pinned list over [context].
Future<void> showPinnedMessages(
  BuildContext context, {
  required Future<List<ChatMessage>?> Function() load,
  void Function(ChatMessage message)? onJump,
  Future<bool> Function(ChatMessage message)? onUnpin,
}) => showAppModal<void>(
  context: context,
  modal: PinnedMessagesDialog(load: load, onJump: onJump, onUnpin: onUnpin),
);
