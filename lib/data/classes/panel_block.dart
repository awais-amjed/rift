import 'package:equatable/equatable.dart';

import 'attachment.dart';

/// The fixed vocabulary a bot draws a panel with (BOTS.md §5, `messages_blocks_shape`).
///
/// A bot never controls a pixel, only a structure. The alternative — letting it
/// send markup or a URL to render — is a stranger's code inside every member's
/// client, with its own sandbox story and its own ideas about your theme.
///
/// **Anything not in this list is not drawn.** That is the safety property, and
/// it is why an unknown type parses to [PanelBlock.unknown] and renders as
/// nothing rather than throwing: a panel from a bot built against a newer
/// vocabulary loses the blocks this client does not have and keeps the rest.
enum PanelBlockType {
  heading,
  text,
  fields,
  progress,
  divider,
  actions,
  select,
  image,

  /// A type this client does not know. Never drawn.
  unknown;

  static PanelBlockType parse(Object? raw) => switch (raw) {
    'heading' => PanelBlockType.heading,
    'text' => PanelBlockType.text,
    'fields' => PanelBlockType.fields,
    'progress' => PanelBlockType.progress,
    'divider' => PanelBlockType.divider,
    'actions' => PanelBlockType.actions,
    'select' => PanelBlockType.select,
    'image' => PanelBlockType.image,
    _ => PanelBlockType.unknown,
  };
}

/// How prominent a button is. Nothing more — a bot picks the weight of an
/// action, not its colour, so a panel cannot paint itself into looking like
/// part of Rift's own chrome.
enum PanelButtonStyle {
  normal,
  primary,
  danger;

  static PanelButtonStyle parse(Object? raw) => switch (raw) {
    'primary' => PanelButtonStyle.primary,
    'danger' => PanelButtonStyle.danger,
    _ => PanelButtonStyle.normal,
  };
}

/// One pressable thing.
class PanelAction extends Equatable {
  final String label;

  /// What comes back to the bot as `action_id`. The bot's own name for it.
  final String action;

  final PanelButtonStyle style;

  /// For a `select` option: what comes back as `action_value`.
  final String? value;

  const PanelAction({
    required this.label,
    required this.action,
    this.style = PanelButtonStyle.normal,
    this.value,
  });

  /// [blockAction] is a `select`'s own action id. Its options carry none —
  /// WIRE.md §5 gives them only a label and a value, since every option of
  /// one menu comes back under the menu's id — so they take the menu's.
  /// Requiring one of their own dropped every option of every menu, and no
  /// menu was ever drawn.
  static PanelAction? tryParse(Object? raw, {String? blockAction}) {
    if (raw is! Map) return null;
    final label = raw['label'];
    final action = blockAction ?? raw['action'];
    // Both are required and both are the bot's: a button with no action id is
    // one nothing can be done with, and one with no label is one nobody can
    // read. Dropping it is better than drawing half of it.
    if (label is! String || action is! String) return null;
    if (label.isEmpty || action.isEmpty || action.length > 64) return null;
    return PanelAction(
      label: label,
      action: action,
      style: PanelButtonStyle.parse(raw['style']),
      value: raw['value'] is String ? raw['value'] as String : null,
    );
  }

  @override
  List<Object?> get props => [label, action, style, value];
}

/// A key/value row inside a `fields` block.
class PanelField extends Equatable {
  final String label;
  final String value;

  const PanelField({required this.label, required this.value});

  static PanelField? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    final value = raw['value'];
    if (label is! String || value is! String) return null;
    return PanelField(label: label, value: value);
  }

  @override
  List<Object?> get props => [label, value];
}

/// An `image` block's picture: a file the bot uploaded, unencrypted, to this
/// server's own attachment bucket, under the channel the panel is in.
///
/// Never a URL. A URL a bot chose would make every member's client fetch from
/// wherever it pointed, handing a stranger the address of everybody in the
/// room and a read receipt per member (BOTS.md §5). The server's own bucket is
/// somewhere every member's client already talks to, and reading from it is
/// held to `chat_attachments_select`: only somebody who can see the channel the
/// file was stored under gets the bytes.
class PanelImage extends Equatable {
  /// The object's path in `chat-<server id>`: `<channel id>/<name>`.
  final String path;

  /// SHA-256 of the bytes, base64. A download that does not match is not
  /// drawn, the same check a file sent unencrypted gets — and a bot can only
  /// name bytes it had, so it cannot point a panel at a file it never read.
  final String sha256;

  /// The picture's size in pixels, so the panel keeps its height while the
  /// bytes arrive rather than jumping when they land.
  final int? width;
  final int? height;

  const PanelImage({
    required this.path,
    required this.sha256,
    this.width,
    this.height,
  });

  /// A channel id, then one plain name: nothing that climbs out of the folder
  /// or reaches into a DM's. Storage would refuse a path the viewer may not
  /// read; this keeps a bot from even asking for one.
  static final _path = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    r'/[A-Za-z0-9_-]{1,100}\.(png|jpe?g|webp|gif)$',
  );

  /// A base64 SHA-256: 32 bytes, 44 characters with one `=` of padding.
  static final _sha256 = RegExp(r'^[A-Za-z0-9+/]{43}=$');

  static PanelImage? tryParse(Map<Object?, Object?> raw) {
    final path = raw['path'];
    final sha256 = raw['sha256'];
    if (path is! String || !_path.hasMatch(path)) return null;
    if (sha256 is! String || !_sha256.hasMatch(sha256)) return null;
    return PanelImage(
      path: path,
      sha256: sha256,
      width: _dimension(raw['width']),
      height: _dimension(raw['height']),
    );
  }

  static int? _dimension(Object? raw) =>
      raw is int && raw > 0 && raw <= 16384 ? raw : null;

  /// The channel the file was stored under, which must be the panel's own.
  String get channelId => path.substring(0, path.indexOf('/'));

  /// The picture as an attachment sent unencrypted, so it is drawn, checked,
  /// cached and opened full-screen by exactly the code a member's own picture
  /// is.
  Attachment get attachment {
    final name = path.substring(path.indexOf('/') + 1);
    final extension = name.substring(name.lastIndexOf('.') + 1);
    return Attachment(
      id: 'panel:$path',
      kind: AttachmentKind.image,
      name: name,
      mime: 'image/${extension == 'jpg' ? 'jpeg' : extension}',
      size: 0,
      storagePath: path,
      keyB64: '',
      nonceB64: '',
      sha256B64: sha256,
      width: width,
      height: height,
    );
  }

  @override
  List<Object?> get props => [path, sha256, width, height];
}

/// One block of a panel.
class PanelBlock extends Equatable {
  final PanelBlockType type;

  /// `heading`, `text`, and a `progress` block's caption.
  final String? text;

  /// `progress`, clamped to 0..1 — a bot sending 7 gets a full bar rather than
  /// a widget laid out seven times its width.
  final double? value;

  /// `fields`.
  final List<PanelField> fields;

  /// `actions` and `select`.
  final List<PanelAction> actions;

  /// `select` only: what comes back as `action_id` whichever option is chosen.
  final String? action;

  /// `image` only. [text] is then its description, for a screen reader.
  final PanelImage? image;

  const PanelBlock({
    required this.type,
    this.text,
    this.value,
    this.fields = const [],
    this.actions = const [],
    this.action,
    this.image,
  });

  static PanelBlock parse(Object? raw) {
    if (raw is! Map) return const PanelBlock(type: PanelBlockType.unknown);
    final type = PanelBlockType.parse(raw['type']);
    final rawValue = raw['value'];
    final action = raw['action'] is String ? raw['action'] as String : null;

    return PanelBlock(
      type: type,
      text: raw['text'] is String ? raw['text'] as String : null,
      value: rawValue is num ? rawValue.toDouble().clamp(0.0, 1.0) : null,
      fields: [
        for (final item in (raw['items'] as List? ?? const []))
          ?PanelField.tryParse(item),
      ],
      actions: [
        if (type == PanelBlockType.select)
          for (final item in (raw['options'] as List? ?? const []))
            ?PanelAction.tryParse(item, blockAction: action)
        else
          for (final item in (raw['items'] as List? ?? const []))
            ?PanelAction.tryParse(item),
      ],
      action: action,
      image: type == PanelBlockType.image ? PanelImage.tryParse(raw) : null,
    );
  }

  /// Whether this block has anything to draw. A `text` block with no text and
  /// an `actions` block whose every button was malformed are both nothing, and
  /// drawing nothing leaves a gap that reads as a bug.
  bool get isDrawable => switch (type) {
    PanelBlockType.unknown => false,
    PanelBlockType.divider => true,
    PanelBlockType.heading || PanelBlockType.text => (text ?? '').isNotEmpty,
    PanelBlockType.progress => value != null,
    PanelBlockType.fields => fields.isNotEmpty,
    PanelBlockType.actions => actions.isNotEmpty,
    PanelBlockType.select => actions.isNotEmpty && (action ?? '').isNotEmpty,
    PanelBlockType.image => image != null,
  };

  @override
  List<Object?> get props => [
    type,
    text,
    value,
    fields,
    actions,
    action,
    image,
  ];
}

/// A whole panel, as it came off the row.
class Panel extends Equatable {
  final List<PanelBlock> blocks;

  const Panel({required this.blocks});

  bool get isEmpty => blocks.isEmpty;

  /// Null when the row carries no panel, which is every message that is not
  /// one. Never throws: a malformed `blocks` column costs its own message, not
  /// the channel it is in.
  ///
  /// [channelId] is the channel the panel was posted in. An `image` stored
  /// under any other is dropped: a picture in a panel is the panel's own, and
  /// one borrowed from another channel would be kept or swept by that
  /// channel's messages rather than this one's.
  static Panel? tryParse(Object? raw, {String? channelId}) {
    if (raw is! Map) return null;
    final list = raw['blocks'];
    if (list is! List) return null;
    final blocks = [
      for (final block in list)
        if (PanelBlock.parse(block) case final parsed
            when parsed.isDrawable &&
                (parsed.image == null || parsed.image!.channelId == channelId))
          parsed,
    ];
    return blocks.isEmpty ? null : Panel(blocks: blocks);
  }

  @override
  List<Object?> get props => [blocks];
}
