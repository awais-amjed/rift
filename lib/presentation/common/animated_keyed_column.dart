import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// A column whose children open into place when they arrive and fold away
/// when they leave, matched from one build to the next by their keys.
///
/// For short lists that change under you — the people in a call. A row that
/// simply appeared shoved everything under it down a whole row in one frame,
/// and one that vanished pulled it up the same way; opening and folding lets
/// the eye follow which row moved.
///
/// **Primed:** whatever is there on the first build is already in place. A
/// sidebar scrolled back into view, or a server switched to, would otherwise
/// replay every arrival at once. Every child needs a [Key]; a leaving child
/// keeps its last widget and its place until it has folded away.
class AnimatedKeyedColumn extends StatefulWidget {
  final List<Widget> children;
  final Duration duration;

  const AnimatedKeyedColumn({
    super.key,
    required this.children,
    this.duration = AppMotion.enter,
  });

  @override
  State<AnimatedKeyedColumn> createState() => _AnimatedKeyedColumnState();
}

class _Entry {
  final Key key;
  Widget child;
  final AnimationController controller;
  bool leaving = false;

  _Entry(this.key, this.child, this.controller);
}

class _AnimatedKeyedColumnState extends State<AnimatedKeyedColumn>
    with TickerProviderStateMixin {
  List<_Entry> _entries = [];

  @override
  void initState() {
    super.initState();
    _entries = [
      for (final child in widget.children) _entry(child, arrived: true),
    ];
  }

  _Entry _entry(Widget child, {required bool arrived}) {
    final controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: arrived ? 1 : 0,
    );
    if (!arrived) controller.forward();
    return _Entry(child.key!, child, controller);
  }

  @override
  void didUpdateWidget(AnimatedKeyedColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = {for (final entry in _entries) entry.key: entry};
    final incoming = {for (final child in widget.children) child.key!};

    // The new order, reusing what was already here.
    final next = <_Entry>[
      for (final child in widget.children)
        if (old[child.key!] case final entry?)
          _returning(entry, child)
        else
          _entry(child, arrived: false),
    ];

    // Whatever left keeps its place — after whichever of its old neighbours
    // is still here — until it has folded away.
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      if (incoming.contains(entry.key)) continue;
      _leave(entry);
      var at = 0;
      for (var j = i - 1; j >= 0; j--) {
        final before = next.indexWhere((e) => e.key == _entries[j].key);
        if (before != -1) {
          at = before + 1;
          break;
        }
      }
      next.insert(at, entry);
    }
    _entries = next;
  }

  _Entry _returning(_Entry entry, Widget child) {
    entry.child = child;
    if (entry.leaving) {
      entry.leaving = false;
      entry.controller.forward();
    }
    return entry;
  }

  void _leave(_Entry entry) {
    if (entry.leaving) return;
    entry.leaving = true;
    entry.controller.reverse().whenComplete(() {
      if (!mounted || !entry.leaving) return;
      setState(() => _entries.remove(entry));
      entry.controller.dispose();
    });
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in _entries)
          KeyedSubtree(
            key: entry.key,
            child: SizeTransition(
              sizeFactor: CurvedAnimation(
                parent: entry.controller,
                curve: AppMotion.arrive,
              ),
              alignment: Alignment.topCenter,
              child: FadeTransition(
                opacity: entry.controller,
                // A leaving row takes no clicks while it folds.
                child: IgnorePointer(
                  ignoring: entry.leaving,
                  child: entry.child,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
