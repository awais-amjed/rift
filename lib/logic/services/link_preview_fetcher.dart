import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/classes/attachment.dart';
import '../../data/classes/pending_attachment.dart';
import '../helper_methods.dart';
import 'link_preview_parser.dart';

/// A preview as the composer holds it before the message goes: the words,
/// and the thumbnail as bytes still to be uploaded.
class PendingLinkPreview {
  final String url;
  final String? title;
  final String? description;
  final String? siteName;
  final PendingAttachment? image;

  const PendingLinkPreview({
    required this.url,
    this.title,
    this.description,
    this.siteName,
    this.image,
  });
}

/// Fetches a page on the sender's device and turns it into a preview.
///
/// Tight on purpose: a few seconds, a few hundred kilobytes of HTML, one
/// picture under a few megabytes shrunk to a thumbnail. Anything past those
/// is not a preview, it is a download the sender did not ask for. Every
/// failure is null — a link with no preview is a link, not an error.
///
/// Not available on the web, where a browser will not hand a page from
/// another origin to script. Previews other people sent still render there.
class LinkPreviewFetcher {
  const LinkPreviewFetcher._();

  static const Duration timeout = Duration(seconds: 6);
  static const int maxHtmlBytes = 512 * 1024;
  static const int maxImageBytes = 5 * 1024 * 1024;

  /// The longest edge of the thumbnail. Enough for a card, small enough
  /// that the encrypted upload is a fraction of a photo.
  static const int thumbnailEdge = 480;

  static const String _userAgent =
      'Mozilla/5.0 (compatible; Rift/1.0; +https://joinrift.app)';

  static bool get isSupported => !kIsWeb;

  static Future<PendingLinkPreview?> fetch(Uri url) async {
    if (!isSupported) return null;
    try {
      final body = await _text(url, maxHtmlBytes);
      if (body == null) return null;
      final meta = LinkPreviewParser.parse(body, url);
      if (meta.isEmpty) return null;

      PendingAttachment? image;
      if (meta.imageUrl != null) {
        image = await _thumbnail(meta.imageUrl!);
      }
      return PendingLinkPreview(
        url: url.toString(),
        title: meta.title,
        description: meta.description,
        siteName: meta.siteName,
        image: image,
      );
    } catch (e) {
      HelperMethods.printDebug('LinkPreviewFetcher: $url – $e');
      return null;
    }
  }

  /// The first [limit] bytes of the page as text, or null when it is not
  /// HTML or does not answer in time.
  static Future<String?> _text(Uri url, int limit) async {
    final bytes = await _bytes(url, limit, accept: 'text/html');
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<Uint8List?> _bytes(
    Uri url,
    int limit, {
    required String accept,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', url)
        ..headers['User-Agent'] = _userAgent
        ..headers['Accept'] = accept
        ..followRedirects = true
        ..maxRedirects = 5;
      final response = await client.send(request).timeout(timeout);
      if (response.statusCode != 200) return null;
      final type = response.headers['content-type'] ?? '';
      if (!type.contains(accept.split('/').first)) return null;

      final buffer = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(timeout)) {
        buffer.add(chunk);
        if (buffer.length > limit) break;
      }
      final bytes = buffer.takeBytes();
      return bytes.length > limit ? bytes.sublist(0, limit) : bytes;
    } finally {
      client.close();
    }
  }

  /// The page's picture, shrunk to [thumbnailEdge] and re-encoded, so what
  /// is uploaded is a thumbnail whatever the site served.
  static Future<PendingAttachment?> _thumbnail(Uri imageUrl) async {
    final raw = await _bytes(imageUrl, maxImageBytes, accept: 'image/*');
    if (raw == null || raw.length >= maxImageBytes) return null;

    final codec = await ui.instantiateImageCodec(
      raw,
      targetWidth: thumbnailEdge,
    );
    final frame = await codec.getNextFrame();
    try {
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return null;
      return PendingAttachment(
        bytes: png.buffer.asUint8List(),
        name: 'preview.png',
        mime: 'image/png',
        kind: AttachmentKind.image,
        width: frame.image.width,
        height: frame.image.height,
      );
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  }
}
