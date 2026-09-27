import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/services/dm_call_split.dart';
import '../../../theme/theme_context.dart';
import '../participants_grid/participants_grid.dart';

/// A DM conversation's call, above its messages, on a desktop.
///
/// Above rather than instead of: the conversation is where the two of you
/// already were, and a link or a screenshot passed mid-call lands in it. The
/// line between them is dragged from the strip under the call, and where it
/// is left is remembered as a share of the pane, so a taller window gets a
/// bigger picture. For more room than a split gives, the call's own strip
/// has Expand.
class DmCallStage extends StatefulWidget {
  /// The pane's height, which the share is taken of.
  final double available;

  const DmCallStage({super.key, required this.available});

  @override
  State<DmCallStage> createState() => _DmCallStageState();
}

class _DmCallStageState extends State<DmCallStage> {
  /// The height while a drag is under way. Stored only when it ends: a drag
  /// reports every pixel, and each report would be a write to disk.
  double? _dragging;

  void _onDrag(DragUpdateDetails details, double from) => setState(
    () => _dragging = DmCallSplit.heightFor(
      widget.available,
      ((_dragging ?? from) + details.delta.dy) / widget.available,
    ),
  );

  void _onDragEnd() {
    final height = _dragging;
    if (height == null) return;
    context.read<AppCubit>().setDmCallStageShare(
      DmCallSplit.shareFor(widget.available, height),
    );
    setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    final share = context.select<AppCubit, double>(
      (c) => c.state.dmCallStageShare,
    );
    final height =
        _dragging ?? DmCallSplit.heightFor(widget.available, share);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: const ParticipantsGrid(embedded: true),
        ),
        _SplitHandle(
          onDrag: (details) => _onDrag(details, height),
          onDragEnd: _onDragEnd,
        ),
      ],
    );
  }
}

/// The strip the split is dragged by: the pane's divider, with a grip in the
/// middle that shows on hover so it reads as something to take hold of.
class _SplitHandle extends StatefulWidget {
  final GestureDragUpdateCallback onDrag;
  final VoidCallback onDragEnd;

  const _SplitHandle({required this.onDrag, required this.onDragEnd});

  @override
  State<_SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<_SplitHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: widget.onDrag,
        onVerticalDragEnd: (_) => widget.onDragEnd(),
        onVerticalDragCancel: widget.onDragEnd,
        child: SizedBox(
          height: K.dmCallHandleHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(height: 1, color: theme.borderPrimary),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _hovered ? theme.textTertiary : theme.borderElevated,
                  borderRadius: BorderRadius.circular(K.radiusPill),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

