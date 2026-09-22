import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../../data/participant_identity.dart';
import '../../../../../data/classes/participant_setting.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/services/fit_aspect.dart';
import '../../../../../logic/services/room_tiles.dart';
import '../../../../../logic/services/stage_fit.dart';
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

  /// How much of the bottom the call controls cover while a cell is focused.
  final double focusBottomInset;

  const ParticipantGridLayout({
    super.key,
    required this.participants,
    required this.participantSettings,
    this.onFocusChanged,
    this.focusTopInset = 0,
    this.focusBottomInset = 0,
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

  /// Kept clear at the stage's foot, beyond its padding, for the floating
  /// call controls — tiles ran under them, names and all.
  static const _barRoom = K.callBarClearance + 8 - 12;

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

  /// Whether [tile] is a share with a picture on it: one this listener is
  /// watching, or this device's own. A share nobody has opened is a button on
  /// an empty card, and gets no more room than a person does.
  static bool _isShowingShare(
    VoiceTile<Participant> tile,
    Set<String> watching,
  ) =>
      tile.isScreenshare &&
      (tile.participant is LocalParticipant ||
          watching.contains(tile.participant.identity));

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles;
    final watching = context.select<LiveKitCubit, Set<String>>(
      (cubit) => cubit.state.subscribedScreenshares,
    );

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
          bottomInset: widget.focusBottomInset,
          // Nothing left to focus on once the share is gone from this screen.
          onWatchStopped: () => _setExpanded(null),
        );
      }
    }

    // Watched screenshares get a hero layout: each share's box is the shape
    // of its picture, as large as fits, with everything else in a row right
    // under it. The row stays under the share rather than beside it so the
    // share keeps the width, and on a tall share it lands behind the floating
    // controls instead of pushing Stop watching under them. Shares nobody has
    // opened go in the row too, or in the grid when nothing is being watched:
    // two unopened streams used to take the whole stage between them.
    final shares = tiles.where((t) => _isShowingShare(t, watching)).toList();
    // Unopened streams lead the row, as they lead the stage.
    final cameras = [
      ...tiles.where((t) => t.isScreenshare && !_isShowingShare(t, watching)),
      ...tiles.where((t) => !t.isScreenshare),
    ];
    if (shares.isNotEmpty && cameras.isNotEmpty) {
      // A phone's height is scarcer.
      final railHeight = context.layoutMode.isCompact ? 84.0 : 100.0;
      const padding = 12.0;
      const gap = 8.0;
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth - padding * 2;
          final shareSpace =
              constraints.maxHeight - padding * 2 - _barRoom - gap - railHeight;
          final slot = (shareSpace - gap * (shares.length - 1)) / shares.length;
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              padding,
              padding,
              padding,
              padding + _barRoom,
            ),
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

    // Everything else is one stage of 16:9 tiles, streams nobody has opened
    // first and a little larger, every row centred — a grid left its last row
    // hanging off to one side. Sized by [stageFit], which picks the column
    // count too: fixed counts put five tiles three to a row in a tall, narrow
    // window and left them a third of its width.
    final streams = tiles.where((t) => t.isScreenshare).toList();
    final people = tiles.where((t) => !t.isScreenshare).toList();
    const padding = 12.0;
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - padding * 2;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight - padding * 2 - _barRoom
            : width;
        final fit = stageFit(
          width: width,
          height: height,
          people: people.length,
          streams: streams.length,
          gap: gap,
        );
        Widget row(List<VoiceTile<Participant>> group, double tileWidth) =>
            Wrap(
              alignment: WrapAlignment.center,
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final tile in group)
                  SizedBox(
                    width: tileWidth,
                    height: tileWidth * 9 / 16,
                    child: _buildTile(tile),
                  ),
              ],
            );
        return Padding(
          padding: const EdgeInsets.only(bottom: _barRoom),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (streams.isNotEmpty) row(streams, fit.streamWidth),
                  if (streams.isNotEmpty && people.isNotEmpty)
                    const SizedBox(height: gap),
                  if (people.isNotEmpty) row(people, fit.tileWidth),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
