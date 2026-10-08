import 'package:equatable/equatable.dart';

import 'attachment.dart';

/// What the sender saw at a link, sealed into the message beside the text.
///
/// Built on the **sender's** device and sent inside the encrypted body, so
/// nobody reading the message ever fetches the page or its picture. The
/// alternative — a preview image URL for each reader to load — hands the
/// site every reader's address and reading time, and lets a link that is
/// unique per message act as a read receipt for each member. Bytes captured
/// once, by the one person who chose the link, close that door; they also
/// keep showing what the sender saw after the page changes.
///
/// The thumbnail rides as an [Attachment] rather than inline: a sealed body
/// is capped at 16 KB on the wire, and a picture does not fit. It is
/// uploaded and encrypted like any other attachment, and kept apart from the
/// message's own attachments so it draws as part of the card, not as a photo
/// the sender posted.
class LinkPreview extends Equatable {
  final String url;
  final String? title;
  final String? description;
  final String? siteName;
  final Attachment? image;

  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.siteName,
    this.image,
  });

  /// Something to draw: a title or a description. A bare URL is not a
  /// preview.
  bool get hasContent =>
      (title?.trim().isNotEmpty ?? false) ||
      (description?.trim().isNotEmpty ?? false);

  /// The host, for the line under the title when the page named no site.
  String get host => Uri.tryParse(url)?.host ?? url;

  Map<String, dynamic> toJson() => {
    'url': url,
    if (title != null) 'title': title,
    if (description != null) 'desc': description,
    if (siteName != null) 'site': siteName,
    if (image != null) 'img': image!.toJson(),
  };

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
    url: json['url'] as String,
    title: json['title'] as String?,
    description: json['desc'] as String?,
    siteName: json['site'] as String?,
    image: json['img'] == null
        ? null
        : Attachment.fromJson(json['img'] as Map<String, dynamic>),
  );

  @override
  List<Object?> get props => [url, title, description, siteName, image];
}
