import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/call_clip_audio.dart';
import '../../../data/classes/stored_clip.dart';
import '../../services/call_clip/clip_library.dart';

part 'clip_history_state.dart';

/// The clips this device keeps, newest first, for the Clips card in a call
/// and the list in Settings (CALLS.md, *Clipping a call*).
///
/// Plain, not hydrated: the clips are on the disk already, sealed, and the
/// list is read from there ([ClipLibrary]). It is read once the seed is
/// handed over ([load]), by whichever of those is opened first, and again
/// each time the library changes, so a press in a call shows at once.
class ClipHistoryCubit extends Cubit<ClipHistoryState> {
  final ClipLibrary _library;
  StreamSubscription<void>? _changes;
  String? _seed;

  ClipHistoryCubit({ClipLibrary? library})
    : _library = library ?? ClipLibrary.instance,
      super(const ClipHistoryState()) {
    _changes = _library.changes.listen((_) => unawaited(_read()));
  }

  /// Reads the list with [seed], the key to the clips, and keeps it for the
  /// reads after.
  Future<void> load(String seed) {
    _seed = seed;
    return _read();
  }

  /// [clip]'s sound, for the trim view; null when it will not open.
  Future<CallClipAudio?> open(StoredClip clip) async {
    final seed = _seed;
    return seed == null ? null : _library.load(seed, clip);
  }

  Future<void> delete(String id) => _library.delete(id);

  Future<void> deleteAll() => _library.clear();

  Future<void> _read() async {
    final seed = _seed;
    if (seed == null || isClosed) return;
    final clips = await _library.list(seed);
    if (isClosed) return;
    emit(ClipHistoryState(clips: clips, loaded: true));
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
