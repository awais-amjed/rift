import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/enums/channel_type.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/channel_search.dart';
import '../../../../theme/app_shadows.dart';
import '../../../../theme/app_text.dart';
import 'widgets/quick_switcher_row.dart';

/// Type-to-jump over the current server's channels.
///
/// Deliberately not an [AppModal]: it has no title, no buttons, and its body
/// scrolls internally — it is a command surface, and the modal chrome would
/// be most of what you'd see.
class QuickSwitcherDialog extends StatefulWidget {
  const QuickSwitcherDialog({super.key});

  @override
  State<QuickSwitcherDialog> createState() => _QuickSwitcherDialogState();
}

class _QuickSwitcherDialogState extends State<QuickSwitcherDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _highlighted = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<Channel> get _results => ChannelSearch.filter(
    context.read<ServerCubit>().state.selectedServer?.channels ?? const [],
    _controller.text,
  );

  void _move(int delta) {
    final count = _results.length;
    if (count == 0) return;
    // Wraps, so holding the arrow key can't strand the highlight at an end.
    setState(() => _highlighted = (_highlighted + delta + count) % count);
  }

  void _openHighlighted() {
    final results = _results;
    if (results.isEmpty) return;
    _open(results[_highlighted.clamp(0, results.length - 1)]);
  }

  void _open(Channel channel) {
    final appCubit = context.read<AppCubit>();
    final chatCubit = context.read<ChannelChatCubit>();

    appCubit.setHomeViewOpen(false);
    if (channel.channelType == ChannelType.text) {
      chatCubit.openChannel(channel.id);
    } else {
      // Voice takes over the centre pane, so any open chat has to close or it
      // would keep the stage hidden behind it.
      chatCubit.closeChannel();
      appCubit.setSelectedChannelId(channel.id);
    }
    Navigator.of(context).pop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _openHighlighted();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final results = _results;

        return Align(
          // Sits high rather than centred: the results grow downward and the
          // eye should stay on the field it is typing into.
          alignment: const Alignment(0, -0.55),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 520,
              constraints: const BoxConstraints(maxHeight: 420),
              decoration: BoxDecoration(
                color: themeState.bgElevated,
                borderRadius: BorderRadius.circular(K.radiusDialog),
                border: Border.all(color: themeState.borderElevated),
                boxShadow: AppShadows.dialog,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildField(themeState),
                  Divider(height: 1, color: themeState.borderPrimary),
                  Flexible(child: _buildResults(themeState, results)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildField(ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        spacing: 10,
        children: [
          Icon(Icons.search_rounded, size: 18, color: themeState.textTertiary),
          Expanded(
            child: Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                onChanged: (_) => setState(() => _highlighted = 0),
                onSubmitted: (_) => _openHighlighted(),
                style: AppText.body.copyWith(color: themeState.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Jump to a channel…',
                  hintStyle: AppText.body.copyWith(
                    color: themeState.textQuaternary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ThemeState themeState, List<Channel> results) {
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(
          'No channels match',
          style: AppText.secondary.copyWith(color: themeState.textQuaternary),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.all(8),
      itemCount: results.length,
      itemBuilder: (context, index) => QuickSwitcherRow(
        channel: results[index],
        isHighlighted: index == _highlighted,
        onTap: () => _open(results[index]),
      ),
    );
  }
}
