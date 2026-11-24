import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../common/anchored_panel.dart';
import '../../../../common/context_menu/context_menu_watcher.dart';
import '../../call_clip/clips_card.dart';
import '../../call_clip/stored_clip_opener.dart';
import 'control_button.dart';

/// Clips in the call's control bar: a way to clip without the shortcut, and
/// the clips this device keeps ([ClipsCard], hanging above the button).
/// Windows and Linux only, where calls are clipped
/// ([HostPlatform.clipsCalls]).
class ClipsButton extends StatefulWidget {
  const ClipsButton({super.key});

  @override
  State<ClipsButton> createState() => _ClipsButtonState();
}

class _ClipsButtonState extends State<ClipsButton> {
  final _buttonKey = GlobalKey();
  bool _open = false;

  Future<void> _show() async {
    final anchor = _buttonKey.currentContext;
    if (anchor == null || _open) return;
    setState(() => _open = true);
    // The call's controls are told, as they are of a menu: the pointer on
    // the card is the pointer gone from the stage, and the bar the card
    // hangs from faded out from under it.
    final watcher = ContextMenuWatcher.maybeOf(context)?..onOpened();
    await showAnchoredPanel<void>(
      anchor: anchor,
      width: ClipsCard.width,
      above: true,
      child: ClipsCard(
        onClip: () => context.read<LiveKitCubit>().clipCall(),
        onOpen: (clip) {
          if (mounted) openStoredClip(context, clip);
        },
      ),
    );
    watcher?.onClosed();
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!HostPlatform.clipsCalls) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ControlButton(
        key: _buttonKey,
        icon: Icons.content_cut_rounded,
        isActive: _open,
        tooltip: 'Clips',
        onTap: _show,
      ),
    );
  }
}
