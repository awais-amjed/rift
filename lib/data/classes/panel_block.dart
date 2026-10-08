import 'package:equatable/equatable.dart';

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

  static PanelAction? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    final action = raw['action'];
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

  const PanelBlock({
    required this.type,
    this.text,
    this.value,
    this.fields = const [],
    this.actions = const [],
    this.action,
  });

  static PanelBlock parse(Object? raw) {
    if (raw is! Map) return const PanelBlock(type: PanelBlockType.unknown);
    final type = PanelBlockType.parse(raw['type']);
    final rawValue = raw['value'];

    return PanelBlock(
      type: type,
      text: raw['text'] is String ? raw['text'] as String : null,
      value: rawValue is num ? rawValue.toDouble().clamp(0.0, 1.0) : null,
      fields: [
        for (final item in (raw['items'] as List? ?? const []))
          ?PanelField.tryParse(item),
      ],
      actions: [
        for (final item
            in (raw['items'] as List? ?? raw['options'] as List? ?? const []))
          ?PanelAction.tryParse(item),
      ],
      action: raw['action'] is String ? raw['action'] as String : null,
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
  };

  @override
  List<Object?> get props => [type, text, value, fields, actions, action];
}

/// A whole panel, as it came off the row.
class Panel extends Equatable {
  final List<PanelBlock> blocks;

  const Panel({required this.blocks});

  bool get isEmpty => blocks.isEmpty;

  /// Null when the row carries no panel, which is every message that is not
  /// one. Never throws: a malformed `blocks` column costs its own message, not
  /// the channel it is in.
  static Panel? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['blocks'];
    if (list is! List) return null;
    final blocks = [
      for (final block in list)
        if (PanelBlock.parse(block) case final parsed when parsed.isDrawable)
          parsed,
    ];
    return blocks.isEmpty ? null : Panel(blocks: blocks);
  }

  @override
  List<Object?> get props => [blocks];
}
