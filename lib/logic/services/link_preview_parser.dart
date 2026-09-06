import 'package:html/parser.dart' as html;

import 'message_markup.dart';

/// The parts of a page a preview is made of, as Open Graph or the page's
/// own tags describe them.
class PageMetadata {
  final String? title;
  final String? description;
  final String? siteName;
  final Uri? imageUrl;

  const PageMetadata({
    this.title,
    this.description,
    this.siteName,
    this.imageUrl,
  });

  bool get isEmpty => title == null && description == null;
}

/// Reads the tags a preview wants out of a page.
///
/// Open Graph first, since that is what a site wrote for exactly this
/// purpose; then Twitter's copies of the same; then the document's own
/// `<title>` and `<meta name="description">`, which every page has. A
/// relative image path is resolved against the page's URL, and a picture
/// that is not `http(s)` is dropped rather than fetched.
class LinkPreviewParser {
  const LinkPreviewParser._();

  static const int maxTitle = 120;
  static const int maxDescription = 300;

  static PageMetadata parse(String body, Uri pageUrl) {
    final doc = html.parse(body);
    String? meta(List<String> keys) {
      for (final key in keys) {
        final byProperty = doc.querySelector('meta[property="$key"]');
        final byName = doc.querySelector('meta[name="$key"]');
        final value = (byProperty ?? byName)?.attributes['content']?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final title =
        meta(['og:title', 'twitter:title']) ??
        doc.querySelector('title')?.text.trim();
    final description = meta([
      'og:description',
      'twitter:description',
      'description',
    ]);
    final siteName = meta(['og:site_name']);
    final image = meta(['og:image', 'og:image:url', 'twitter:image']);

    Uri? imageUrl;
    if (image != null) {
      final resolved = pageUrl.resolve(image);
      if (resolved.scheme == 'http' || resolved.scheme == 'https') {
        imageUrl = resolved;
      }
    }

    return PageMetadata(
      title: _clip(_oneLine(title), maxTitle),
      description: _clip(_oneLine(description), maxDescription),
      siteName: _clip(_oneLine(siteName), maxTitle),
      imageUrl: imageUrl,
    );
  }

  static String? _oneLine(String? s) {
    if (s == null) return null;
    final collapsed = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.isEmpty ? null : collapsed;
  }

  static String? _clip(String? s, int max) {
    if (s == null || s.length <= max) return s;
    return '${s.substring(0, max - 1).trimRight()}…';
  }
}

/// Finds the link a message would preview.
class LinkDetector {
  const LinkDetector._();

  /// The first address in [text], read by the same parser that draws it, so
  /// the card and the tappable stretch always agree on what the link was.
  static Uri? firstUrl(String text) {
    for (final span in parseMessageMarkup(text)) {
      final link = span.link;
      if (link != null) return Uri.tryParse(link);
    }
    return null;
  }
}
