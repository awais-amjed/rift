import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/media_entry.dart';
import '../../../data/repositories/directory_icon_repository.dart';
import '../../services/media_store.dart';

part 'media_state.dart';

/// Which [MediaStore] a picture lives in.
enum MediaKind { image, attachment }

/// Every picture the app has fetched, for widgets to draw.
///
/// The one place a widget reads a picture from. A widget asks with [want] and
/// selects its own entry from the state, so every widget showing the same
/// picture shows the same thing: when one fetch lands, they all draw it, and
/// a fetch that failed for one is retried for all. Before this each widget
/// held its own copy, and a single failed download left one spot on initials
/// for the rest of the session.
///
/// Mirrors [MediaStore] rather than holding the bytes itself, because the
/// code that fetches and uploads — other cubits, the chat uploader — writes
/// there, and must not have to know about this cubit.
class MediaCubit extends Cubit<MediaState> {
  final MediaStore _images;
  final MediaStore _attachments;
  final DirectoryIconRepository _icons;

  late final StreamSubscription<String> _imageSub;
  late final StreamSubscription<String> _attachmentSub;

  /// A failed fetch waiting to be tried again, by kind and path.
  final Map<String, Timer> _retries = {};

  /// How long to wait before each retry of a failed fetch. Past the last,
  /// the picture is fetched again only when something asks for it anew.
  static const List<Duration> backoff = [
    Duration(seconds: 3),
    Duration(seconds: 15),
    Duration(minutes: 1),
  ];

  final List<Duration> _backoff;

  MediaCubit({
    MediaStore? images,
    MediaStore? attachments,
    DirectoryIconRepository? icons,
    List<Duration> retryAfter = backoff,
  }) : _images = images ?? MediaStore.images,
       _backoff = retryAfter,
       _attachments = attachments ?? MediaStore.attachments,
       _icons = icons ?? DirectoryIconRepository(),
       super(
         MediaState(
           images: (images ?? MediaStore.images).snapshot,
           attachments: (attachments ?? MediaStore.attachments).snapshot,
         ),
       ) {
    _imageSub = _images.changes.listen(
      (path) => _mirror(MediaKind.image, path),
    );
    _attachmentSub = _attachments.changes.listen(
      (path) => _mirror(MediaKind.attachment, path),
    );
  }

  /// Fetch [path] with [fetch] unless it is here or on its way.
  ///
  /// [fetch] has to go through the [MediaStore] for [kind] — the server
  /// cubit's `loadAvatar`, a chat's attachment loader — which is what puts the
  /// bytes where every widget sees them. It is kept while the fetch keeps
  /// failing, to try again on the [backoff] schedule.
  void want(MediaKind kind, String path, Future<Uint8List?> Function() fetch) {
    final status = _store(kind)[path]?.status;
    if (status == MediaStatus.success || status == MediaStatus.loading) return;
    if (_retries.containsKey(_retryKey(kind, path))) return;
    unawaited(_attempt(kind, path, fetch, 0));
  }

  /// [want] for a directory listing's icon, from central's bucket.
  void wantDirectoryIcon(String path) => want(
    MediaKind.image,
    path,
    () => _images.load(path, () => _icons.download(path)),
  );

  Future<void> _attempt(
    MediaKind kind,
    String path,
    Future<Uint8List?> Function() fetch,
    int tries,
  ) async {
    final bytes = await fetch();
    if (isClosed || bytes != null || tries >= _backoff.length) return;
    // Gone from the store while it was failing: cleared or deleted, so
    // nothing wants it back.
    if (_store(kind)[path] == null) return;
    final key = _retryKey(kind, path);
    _retries[key] = Timer(_backoff[tries], () {
      _retries.remove(key);
      if (!isClosed) unawaited(_attempt(kind, path, fetch, tries + 1));
    });
  }

  void _mirror(MediaKind kind, String path) {
    if (isClosed) return;
    final entry = _store(kind)[path];
    final current = kind == MediaKind.image ? state.images : state.attachments;
    if (current[path] == entry) return;
    final next = Map<String, MediaEntry>.of(current);
    if (entry == null) {
      next.remove(path);
    } else {
      next[path] = entry;
    }
    emit(
      kind == MediaKind.image
          ? state.copyWith(images: next)
          : state.copyWith(attachments: next),
    );
  }

  MediaStore _store(MediaKind kind) =>
      kind == MediaKind.image ? _images : _attachments;

  static String _retryKey(MediaKind kind, String path) => '${kind.name}:$path';

  @override
  Future<void> close() async {
    for (final timer in _retries.values) {
      timer.cancel();
    }
    _retries.clear();
    await _imageSub.cancel();
    await _attachmentSub.cancel();
    return super.close();
  }
}
