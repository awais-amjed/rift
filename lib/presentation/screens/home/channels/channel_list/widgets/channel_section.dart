import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/apis/channels_api.dart';
import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../data/repositories/session_repository.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../theme/app_shadows.dart';
import '../../../../../theme/theme_context.dart';

/// Wraps the part of a row that picks it up, or hands it back unchanged when
/// the list cannot be reordered.
typedef ChannelGrip = Widget Function(Widget child);

/// One section of the channel list, text or voice, as a sliver: in the order
/// the server keeps, and draggable into a new one by whoever may manage
/// channels.
///
/// The order a manager drops is shown until the server answers, and no
/// longer. Either way the server's list replaces it then, so a refused move
/// puts the rows back rather than leaving a sidebar the server disagrees with.
class ChannelSection extends StatefulWidget {
  final List<Channel> channels;

  /// Whether rows can be picked up. Off for members, and on a phone, where a
  /// held finger already opens a channel's menu.
  final bool canReorder;

  /// Builds one row; [grip] wraps whatever part of it a drag starts from.
  final Widget Function(BuildContext context, Channel channel, ChannelGrip grip)
  rowBuilder;

  const ChannelSection({
    super.key,
    required this.channels,
    required this.canReorder,
    required this.rowBuilder,
  });

  /// Half the gap between two channel rows, above and below each.
  ///
  /// The list's, not the rows': a voice channel is a plain row until someone
  /// joins and a card after, and a gap the card carried itself would move the
  /// channel's name the moment it turned into one. Here both shapes get the
  /// same, so two cards side by side don't touch, and neither do two lit
  /// text rows.
  static const double rowGap = 2;

  @override
  State<ChannelSection> createState() => _ChannelSectionState();
}

class _ChannelSectionState extends State<ChannelSection> {
  /// The ids in the order last dropped, while the server has not answered.
  List<String>? _pending;

  /// Which drop [_pending] belongs to, so an older answer arriving after a
  /// newer drop does not clear it.
  int _moves = 0;

  List<Channel> get _shown {
    final pending = _pending;
    if (pending == null) return widget.channels;
    final rank = {for (var i = 0; i < pending.length; i++) pending[i]: i};
    // A channel that arrived since the drop has no rank and goes last, as a
    // new one does on the server.
    return [...widget.channels]..sort(
      (a, b) => (rank[a.id] ?? pending.length).compareTo(
        rank[b.id] ?? pending.length,
      ),
    );
  }

  Future<void> _move(int from, int to) async {
    if (from == to) return;
    final ids = [for (final c in _shown) c.id];
    ids.insert(to, ids.removeAt(from));
    final move = ++_moves;
    setState(() => _pending = ids);

    final result = await ChannelsApi(
      session: context.read<SessionRepository>(),
    ).reorderChannels(ids);
    if (!result.success) {
      HelperMethods.showError(error: result.error);
    }
    if (mounted && move == _moves) setState(() => _pending = null);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (!widget.canReorder) {
      return SliverList.builder(
        itemCount: shown.length,
        itemBuilder: (context, i) => _row(context, shown[i], (w) => w),
      );
    }
    return SliverReorderableList(
      itemCount: shown.length,
      proxyDecorator: _carried,
      onReorderItem: _move,
      itemBuilder: (context, i) => _row(
        context,
        shown[i],
        (w) => ReorderableDragStartListener(index: i, child: w),
      ),
    );
  }

  Widget _row(BuildContext context, Channel channel, ChannelGrip grip) =>
      Padding(
        key: ValueKey(channel.id),
        padding: const EdgeInsets.symmetric(vertical: ChannelSection.rowGap),
        child: widget.rowBuilder(context, channel, grip),
      );

  /// The row while it is being carried: lifted onto the elevated surface.
  ///
  /// Flutter's default is a Material with its own elevation and square
  /// corners. A text row has no fill of its own, so carried bare it would be a
  /// name floating over the names it passes.
  static Widget _carried(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value);
        final theme = context.theme;
        return Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color.lerp(
                theme.bgElevated.withValues(alpha: 0),
                theme.bgElevated,
                t,
              ),
              borderRadius: BorderRadius.circular(K.radiusCard),
              boxShadow: t > 0 ? AppShadows.popover : null,
            ),
            child: child,
          ),
        );
      },
    );
  }
}
