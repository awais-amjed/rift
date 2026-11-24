import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../theme/app_motion.dart';
import 'app_modal_header_button.dart';

/// A list's refresh: its arrow turns once on every press, and goes on
/// turning for as long as the list takes to come back.
///
/// A list that came back at once looked the same as a press that missed, so
/// a whole turn is shown however quick the answer. A press while one is
/// still turning is taken as the same press.
class RefreshButton extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final String tooltip;

  const RefreshButton({
    super.key,
    required this.onRefresh,
    this.tooltip = 'Refresh the list',
  });

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(vsync: this, duration: AppMotion.turn);
  late final _turns = CurvedAnimation(parent: _turn, curve: AppMotion.settle);
  bool _busy = false;

  @override
  void dispose() {
    _turns.dispose();
    _turn.dispose();
    super.dispose();
  }

  Future<void> _press() async {
    if (_busy) return;
    _busy = true;
    var done = false;
    unawaited(
      widget.onRefresh().catchError((_) {}).whenComplete(() => done = true),
    );
    try {
      do {
        await _turn.forward(from: 0).orCancel;
      } while (!done && mounted);
    } on TickerCanceled {
      // Closed mid-turn.
    }
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return AppModalHeaderButton(
      icon: Icons.refresh,
      tooltip: widget.tooltip,
      turns: _turns,
      onPressed: _press,
    );
  }
}
