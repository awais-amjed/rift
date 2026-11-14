import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../data/constants.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../theme/theme_context.dart';
import '../loading_dots.dart';

/// A conversation's history, with a pill at its top while the latest messages
/// are still being fetched.
///
/// A conversation opens on the copy this device saved, and the server's page
/// replaces it when it lands. On a distant server that is a second or more,
/// and the saved copy looks exactly like the conversation as it stands, so
/// without this nothing told the reader that newer messages were on the way.
///
/// It floats rather than taking space, so the list does not move when it
/// comes or goes, and lets the pointer through to the rows under it. It waits
/// [_delay] before appearing, so a server that answers at once never flashes it.
class FetchingLatestOverlay extends StatefulWidget {
  final bool fetching;
  final Widget child;

  const FetchingLatestOverlay({
    super.key,
    required this.fetching,
    required this.child,
  });

  @override
  State<FetchingLatestOverlay> createState() => _FetchingLatestOverlayState();
}

class _FetchingLatestOverlayState extends State<FetchingLatestOverlay> {
  static const _delay = Duration(milliseconds: 250);

  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    if (widget.fetching) _arm();
  }

  @override
  void didUpdateWidget(FetchingLatestOverlay old) {
    super.didUpdateWidget(old);
    if (widget.fetching == old.fetching) return;
    if (widget.fetching) {
      _arm();
    } else {
      _timer?.cancel();
      _shown = false;
    }
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(_delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSlide(
                offset: _shown ? Offset.zero : const Offset(0, -0.4),
                duration: AppMotion.enter,
                curve: AppMotion.settle,
                child: AnimatedOpacity(
                  opacity: _shown ? 1 : 0,
                  duration: _shown ? AppMotion.enter : AppMotion.state,
                  curve: AppMotion.settle,
                  child: const _Pill(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
      decoration: BoxDecoration(
        color: theme.bgElevated,
        borderRadius: BorderRadius.circular(K.radiusPill),
        border: Border.all(color: theme.borderElevated),
        boxShadow: AppShadows.floatingBar,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LoadingDots(color: theme.accentBright),
          const SizedBox(width: 8),
          Text(
            'Loading new messages',
            style: AppText.label.copyWith(
              fontWeight: FontWeight.w400,
              color: theme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
