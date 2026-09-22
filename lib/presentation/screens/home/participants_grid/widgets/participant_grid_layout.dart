import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../../data/participant_identity.dart';
import '../../../../../data/classes/participant_setting.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/fit_aspect.dart';
import '../../../../../logic/services/room_tiles.dart';
import '../../../../../logic/services/voice_tiles.dart';
import '../../../../responsive/shell_scope.dart';
import '../participants_tile/participant_tile.dart';
import '../participants_tile/sound_share_tile.dart';
import 'camera_rail.dart';

/// Grid view displaying all participants with adaptive column count.
class ParticipantGridLayout extends StatefulWidget {
  final List<Participant> participants;
  final Map<String, ParticipantSetting> participantSettings;

  /// Told when a cell starts or stops filling the stage.
  final ValueChanged<bool>? onFocusChanged;

  /// How much of the top a floating bar covers while a cell is focused.
  final double focusTopInset;

  const ParticipantGridLayout({
    super.key,
    required this.participants,
    required this.participantSettings,
    this.onFocusChanged,
    this.focusTopInset = 0,
  });

  @override
  State<ParticipantGridLayout> createState() => _ParticipantGridLayoutState();
}

class _ParticipantGridLayoutState extends State<ParticipantGridLayout> {
  /// Which cell is expanded, by [_keyOf] rather than by identity — one person
  /// sharing from a phone owns two cells under the same identity, and an
  /// identity alone cannot say which of them was tapped.
  String? _expandedKey;

  /// Held from [initState] so [dispose] can still reach it: leaving the call
  /// with a tile focused must not leave the member list hidden behind it.
  late final AppCubit _appCubit;

  /// Each share's picture shape, by [_keyOf], once its first frame arrives.
  final Map<String, double> _aspects = {};

  /// What a share is drawn as until its picture says otherwise.
  static const _defaultAspect = 16 / 9;

  void _onAspectRatio(String key, double ratio) {
    if (!mounted || _aspects[key] == ratio) return;
    setState(() => _aspects[key] = ratio);
  }

  @override
  void initState() {
    super.initState();
    _appCubit = context.read<AppCubit>();
  }

  @override
  void dispose() {
    if (_expandedKey != null) _appCubit.setStageFocused(false);
    super.dispose();
  }

  /// Focus one cell, or none. The member list follows: hidden while a cell
  /// fills the stage, back to how it was after.
  void _setExpanded(String? key) {
    if (key == _expandedKey) return;
    final wasFocused = _expandedKey != null;
    setState(() => _expandedKey = key);
    if (wasFocused == (key != null)) return;
    _appCubit.setStageFocused(key != null);
    widget.onFocusChanged?.call(key != null);
  }

  static String _keyOf(VoiceTile<Participant> tile) =>
      '${tile.participant.identity}${tile.isScreenshare ? '#share' : ''}';

  /// The cells to draw. A share is a cell, not a participant — see
  /// [voiceTilesFor].
  List<VoiceTile<Participant>> get _tiles =>
      roomVoiceTiles(widget.participants);

  /// Whether this listener has muted [identity] for themselves.
  ///
  /// Absent means not muted: a person nobody has an opinion about has no row.
  bool _mutedFor(String identity) =>
      widget
          .participantSettings[ParticipantIdentity.userIdOf(identity)]
          ?.muted ??
      false;

  Widget _buildTile(VoiceTile<Participant> tile) {
    // A shared track has nothing to enlarge, so it is a cell and never a
    // stage: no tap to focus, and no focused layout to fall back to.
    if (tile.isSoundShare) {
      return SoundShareTile(participant: tile.participant);
    }
    final key = _keyOf(tile);
    return ParticipantTileWidget(
      participant: tile.participant,
      isScreenshare: tile.isScreenshare,
      isMuted: _mutedFor(tile.participant.identity),
      onTap: () => _onTileTapped(_keyOf(tile)),
      // Watching a share is asking to look at it, so it opens focused; a tap
      // on it brings the others back.
      onWatchStarted: () => _setExpanded(key),
      onAspectRatio: tile.isScreenshare
          ? (ratio) => _onAspectRatio(key, ratio)
          : null,
    );
  }

  /// Collapse if already expanded, otherwise expand this one.
  void _onTileTapped(String key) =>
      _setExpanded(_expandedKey == key ? null : key);

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles;

    // If a tile is expanded, show only that tile in full view
    if (_expandedKey != null) {
      final expanded = tiles
          .where((t) => _keyOf(t) == _expandedKey)
          .firstOrNull;
      if (expanded == null) {
        // The cell went away — the sharer stopped, or the participant left.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setExpanded(null);
        });
      } else {
        return ParticipantTileWidget(
          participant: expanded.participant,
          isScreenshare: expanded.isScreenshare,
          isMuted: _mutedFor(expanded.participant.identity),
          onTap: () => _onTileTapped(_keyOf(expanded)),
          isExpanded: true,
          topInset: widget.focusTopInset,
          // Nothing left to focus on once the share is gone from this screen.
          onWatchStopped: () => _setExpanded(null),
        );
      }
    }

    // Screenshares get a hero layout: each share's box is the shape of its
    // picture, as large as fits, with the camera tiles in a row right under
    // it. The row stays under the share rather than beside it so the share
    // keeps the width, and on a tall share it lands behind the floating
    // controls instead of pushing Stop watching under them.
    final shares = tiles.where((t) => t.isScreenshare).toList();
    final cameras = tiles.where((t) => !t.isScreenshare).toList();
    if (shares.isNotEmpty && cameras.isNotEmpty) {
      // Tall enough on desktop that a full-height share clears the control
      // bar, which floats 28px up and is about 64px tall. A phone's height
      // is scarcer.
      final railHeight = context.layoutMode.isCompact ? 84.0 : 100.0;
      const padding = 12.0;
      const gap = 8.0;
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth - padding * 2;
          final shareSpace =
              constraints.maxHeight - padding * 2 - gap - railHeight;
          final slot = (shareSpace - gap * (shares.length - 1)) / shares.length;
          return Padding(
            padding: const EdgeInsets.all(padding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < shares.length; i++) ...[
                  if (i > 0) const SizedBox(height: gap),
                  SizedBox.fromSize(
                    size: fitAspect(
                      _aspects[_keyOf(shares[i])] ?? _defaultAspect,
                      Size(width, slot),
                    ),
                    child: _buildTile(shares[i]),
                  ),
                ],
                const SizedBox(height: gap),
                CameraRail(
                  count: cameras.length,
                  height: railHeight,
                  gap: gap,
                  itemBuilder: (context, index) => _buildTile(cameras[index]),
                ),
              ],
            ),
          );
        },
      );
    }

    // Compute grid columns based on how many cells there are
    int cols = 1;
    if (tiles.length >= 2) cols = 2;
    if (tiles.length >= 5) cols = 3;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate max width regarding the aspect ratio to ensure the grid fits vertically
        final int rows = (tiles.length / cols).ceil();
        const double gridPadding = 12.0;
        const double gridSpacing = 8.0;

        // Available height excludes vertical padding
        final double availableHeight =
            constraints.maxHeight - (gridPadding * 2);

        // Height taken by spacing between rows
        final double spacingHeight = (rows > 1) ? (rows - 1) * gridSpacing : 0;

        // Remaining height for participant tiles
        final double heightForTiles = availableHeight - spacingHeight;

        double maxWidthConstraint = double.infinity;

        if (heightForTiles > 0 && rows > 0 && constraints.maxHeight.isFinite) {
          final double maxTileHeight = heightForTiles / rows;
          final double maxTileWidth = maxTileHeight * (16 / 9);

          final double spacingWidth = (cols > 1) ? (cols - 1) * gridSpacing : 0;
          final double contentWidth = (maxTileWidth * cols) + spacingWidth;

          maxWidthConstraint = contentWidth + (gridPadding * 2);
        }

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidthConstraint),
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(gridPadding),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: gridSpacing,
                mainAxisSpacing: gridSpacing,
                childAspectRatio: 16 / 9,
              ),
              itemCount: tiles.length,
              itemBuilder: (context, index) => _buildTile(tiles[index]),
            ),
          ),
        );
      },
    );
  }
}
