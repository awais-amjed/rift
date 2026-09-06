import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/classes/link_preview.dart';
import 'package:rift/data/classes/message_body.dart';

void main() {
  const image = Attachment(
    id: 'p1',
    kind: AttachmentKind.image,
    name: 'preview.png',
    mime: 'image/png',
    size: 1234,
    storagePath: 'chan/p1.bin',
    keyB64: 'k',
    nonceB64: 'n',
    width: 480,
    height: 240,
  );

  test('a preview rides in the sealed body and comes back whole', () {
    const body = MessageBody(
      text: 'look https://a.example',
      preview: LinkPreview(
        url: 'https://a.example',
        title: 'A',
        description: 'About a',
        siteName: 'Example',
        image: image,
      ),
    );
    final back = MessageBody.decode(body.encode());
    final p = back.preview!;
    expect(p.url, 'https://a.example');
    expect(p.title, 'A');
    expect(p.description, 'About a');
    expect(p.siteName, 'Example');
    expect(p.image?.storagePath, 'chan/p1.bin');
    // The thumbnail is the card's, not one of the message's own pictures.
    expect(back.attachments, isEmpty);
  });

  test('a body without one decodes to none, as every old message does', () {
    expect(
      MessageBody.decode(const MessageBody(text: 'hi').encode()).preview,
      isNull,
    );
    expect(MessageBody.decode('plain old text').preview, isNull);
  });

  test('a bare URL with nothing to say is not worth a card', () {
    expect(const LinkPreview(url: 'https://x.example').hasContent, isFalse);
    expect(
      const LinkPreview(url: 'https://x.example', title: 't').hasContent,
      isTrue,
    );
    expect(const LinkPreview(url: 'https://x.example/p').host, 'x.example');
  });
}
