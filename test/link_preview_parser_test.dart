import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/link_preview_parser.dart';

void main() {
  group('finding the link', () {
    test('the first http(s) link, and only that', () {
      expect(
        LinkDetector.firstUrl(
          'see https://a.example/x and http://b.example',
        ).toString(),
        'https://a.example/x',
      );
      expect(LinkDetector.firstUrl('ftp://files.example/x'), isNull);
      expect(LinkDetector.firstUrl('just example.com here'), isNull);
    });

    test('sentence punctuation is not part of the address', () {
      expect(
        LinkDetector.firstUrl('look: https://a.example/path.').toString(),
        'https://a.example/path',
      );
      expect(
        LinkDetector.firstUrl('(https://a.example/p)').toString(),
        'https://a.example/p',
      );
      // A bracket that closes one inside the path stays.
      expect(
        LinkDetector.firstUrl('https://w.example/Foo_(bar)').toString(),
        'https://w.example/Foo_(bar)',
      );
    });
  });

  group('reading the page', () {
    final page = Uri.parse('https://site.example/post/1');

    test('prefers Open Graph, resolves a relative image', () {
      final m = LinkPreviewParser.parse('''
        <html><head>
          <title>Fallback title</title>
          <meta property="og:title" content="  The  real title ">
          <meta property="og:description" content="What it is about.">
          <meta property="og:site_name" content="Site">
          <meta property="og:image" content="/img/cover.png">
        </head></html>''', page);
      expect(m.title, 'The real title');
      expect(m.description, 'What it is about.');
      expect(m.siteName, 'Site');
      expect(m.imageUrl.toString(), 'https://site.example/img/cover.png');
    });

    test('falls back to the document title and meta description', () {
      final m = LinkPreviewParser.parse(
        '''
        <html><head><title>Plain page</title>
        <meta name="description" content="Described plainly."></head></html>''',
        page,
      );
      expect(m.title, 'Plain page');
      expect(m.description, 'Described plainly.');
      expect(m.siteName, isNull);
      expect(m.imageUrl, isNull);
    });

    test('drops a picture it would not fetch, and clips long text', () {
      final m = LinkPreviewParser.parse(
        '''
        <meta property="og:title" content="${'x' * 300}">
        <meta property="og:image" content="data:image/png;base64,AAAA">''',
        page,
      );
      expect(m.title!.length, LinkPreviewParser.maxTitle);
      expect(m.title!.endsWith('…'), isTrue);
      expect(m.imageUrl, isNull);
    });

    test('a page with nothing to say is empty', () {
      expect(LinkPreviewParser.parse('<p>hi</p>', page).isEmpty, isTrue);
    });
  });
}
