import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../data/repositories/blob/blob_reader.dart';
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

  /// The most a video's card downloads by itself to draw its poster, the
  /// size a file is read into memory to send at: past it the card stays
  /// dark until played.
  static const int posterMaxBytes = 16 * 1024 * 1024;

  /// [video]'s first picture as a JPEG, its longer side at most [longest]
  /// pixels; null where it cannot be made.
  static Future<Uint8List?> poster(Uint8List video, {int longest = 880}) =>
      kIsWeb
      ? WebChatClip.poster(video, longest: longest)
      : RustChatClip.poster(video, longest: longest);

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
