import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../data/classes/pending_attachment.dart';
import '../../../data/repositories/blob/blob_reader.dart';
import '../../../data/repositories/blob/file_chunks.dart';
import '../../../src/rust/api/clips.dart';
import 'rust_chat_clip.dart';
import 'web_chat_clip.dart';

/// A video from the chat, played from memory with the system's own
/// decoders: by Rust into a runner texture on Linux and Windows
/// ([RustChatClip], `rust/src/clips`), by the browser's own `<video>` on the
/// web ([WebChatClip]).
///
/// An attachment is decrypted message content and never goes to disk, so
/// the player reads it from memory, through a [BlobReader]: a big one is
/// fetched and opened a chunk at a time as the player wants it, so it starts
/// at once and is never held whole. One per card that is playing; the card
/// closes it when it goes.
abstract class ChatClip {
  /// Whether this build plays a chat video itself. Where not, the card
  /// offers the file to save.
  static final bool available = kIsWeb
      ? WebChatClip.available
      : (Platform.isLinux || Platform.isWindows) && RustChatClip.available();

  /// Opens the video [file] reads, paused on its first picture, its sound
  /// to play on [output] (the device id the app's output setting holds; null
  /// for the default). The clip owns [file] from here and closes it with
  /// itself. Null, with nothing left behind, when it would not open.
  static Future<({ChatClip? clip, String? error})> open(
    BlobReader file, {
    String? output,
  }) => kIsWeb
      ? WebChatClip.open(file, output: output)
      : RustChatClip.open(file, output: output);

  /// The most a video that can only be fetched whole — sealed in one piece,
  /// or sent unencrypted — is fetched into memory to play. Past it the card
  /// offers it to save.
  static const int wholeMaxBytes = 64 * 1024 * 1024;

  /// The most the browser's player is handed in memory to draw a poster
  /// from: the size a file is read into memory to send at. A bigger one's
  /// is drawn from its blob URL ([posterToSend]).
  static const int posterMaxBytes = 16 * 1024 * 1024;

  /// The poster a video being sent carries (`Attachment.poster`): its first
  /// picture, made from the file on this device before it goes, so nobody's
  /// card fetches the video to show one. A big one is read where it lies,
  /// never into memory. Null where this build cannot make one.
  static Future<Uint8List?> posterToSend(PendingAttachment video) async {
    if (!available) return null;
    if (video.bytes case final bytes?) return poster(MemoryBlobReader(bytes));
    final file = video.file;
    if (file == null) return null;
    if (kIsWeb) {
      return file.path.isEmpty ? null : WebChatClip.posterAt(file.path);
    }
    final reader = fileBlobReader(file, video.size);
    return reader == null ? null : poster(reader);
  }

  /// The first picture of the video [file] reads, as a JPEG, its longer
  /// side at most [longest] pixels; null where it cannot be made. Owns
  /// [file] and closes it.
  static Future<Uint8List?> poster(BlobReader file, {int longest = 880}) =>
      kIsWeb
      ? _webPoster(file, longest)
      : RustChatClip.poster(file, longest: longest);

  /// The browser's player takes the file whole.
  static Future<Uint8List?> _webPoster(BlobReader file, int longest) async {
    try {
      if (file.length > posterMaxBytes) return null;
      final video = await file.readFully(0, file.length);
      return await WebChatClip.poster(video, longest: longest);
    } catch (_) {
      return null;
    } finally {
      await file.close();
    }
  }

  /// What the player says about this clip: its picture's shape, the end, a
  /// failure. Said before anyone listens, it waits.
  Stream<ClipEvent> get events;

  /// The playing picture, to fill the card's box. Drawn only once a
  /// [ClipEventKind.pictureSize] has come.
  Widget picture();

  /// Whether it started. A browser may refuse sound that no click asked
  /// for just then, and the card then stays paused for the next one.
  Future<bool> play();

  Future<void> pause();

  Future<void> seek(Duration to);

  /// 1 as recorded.
  Future<void> setVolume(double volume);

  /// Where it is, and how long it is, where the player knows.
  ({Duration? position, Duration? length}) time();

  /// Stops it and lets the file go.
  Future<void> close();
}
