/// The native half of [web_chat_clip.dart]: off the web, Rust plays.
library;

import 'package:flutter/foundation.dart';

import '../../../data/repositories/blob/blob_reader.dart';
import 'chat_clip.dart';

/// Never used off the web.
abstract class WebChatClip implements ChatClip {
  static const bool available = false;

  static Future<({ChatClip? clip, String? error})> open(
    BlobReader file, {
    String? output,
  }) async => (clip: null, error: 'Not a browser');

  static Future<Uint8List?> poster(
    Uint8List video, {
    int longest = 880,
  }) async => null;
}
