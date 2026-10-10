import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../data/constants.dart';
import '../../../theme/theme_context.dart';

/// Where a bot command sits in the composer's text: the verb, the argument,
/// and what the verb says it wants (`BotCommands.shapeOf`).
typedef CommandShape = ({TextRange verb, TextRange argument, String? usage});

/// Draws a bot command apart from an ordinary message, behind the field's own
/// text: what follows the verb boxed like inline code, as it will read once
/// sent (`commandMessageSpan`), and — while that is still empty — the
/// command's usage as a placeholder. The verb's accent and the code face come
/// from the controller (`EmojiTextEditingController.command`).
///
/// Behind the text rather than in it, so the field keeps holding exactly the
/// line that is sent: the caret, selection, the `@` and `/` menus and the
/// unencrypted notice all keep reading one string. The boxes are measured
/// from the field's laid-out text a frame after it changes, so they follow
/// wrapping and emoji without a second copy of the layout.
class ComposerCommandBackdrop extends StatefulWidget {
  final TextEditingController controller;
  final CommandShape? shape;

  /// The field's text style, so the placeholder sits on the same baseline as
  /// what will be typed over it.
  final TextStyle placeholderStyle;
  final Widget child;

  const ComposerCommandBackdrop({
    super.key,
    required this.controller,
    required this.shape,
    required this.placeholderStyle,
    required this.child,
  });

  @override
  State<ComposerCommandBackdrop> createState() =>
      _ComposerCommandBackdropState();
}

class _ComposerCommandBackdropState extends State<ComposerCommandBackdrop> {
  final GlobalKey _field = GlobalKey();
  List<Rect> _argument = const [];

  /// Where the placeholder goes: just after the verb's space, on its line.
  Offset? _placeholderAt;
  bool _measuring = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_measureSoon);
  }

  @override
  void didUpdateWidget(ComposerCommandBackdrop old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_measureSoon);
      widget.controller.addListener(_measureSoon);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_measureSoon);
    super.dispose();
  }

  /// After this frame's layout: the field has only then placed the new text.
  void _measureSoon() {
    if (_measuring) return;
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    final shape = widget.shape;
    final me = context.findRenderObject() as RenderBox?;
    final editable = _findEditable(_field.currentContext?.findRenderObject());
    final text = widget.controller.text;
    if (shape == null ||
        me == null ||
        editable == null ||
        !me.hasSize ||
        shape.argument.end > text.length) {
      _set(const [], null);
      return;
    }
    final origin = me.globalToLocal(editable.localToGlobal(Offset.zero));
    List<Rect> boxes(TextRange range) => [
      for (final box in editable.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      ))
        box.toRect().shift(origin),
    ];
    final empty = shape.argument.isCollapsed;
    _set(
      empty ? const [] : boxes(shape.argument),
      empty
          ? editable
                    .getLocalRectForCaret(
                      TextPosition(offset: shape.argument.start),
                    )
                    .topLeft +
                origin
          : null,
    );
  }

  void _set(List<Rect> argument, Offset? placeholderAt) {
    if (_sameRects(argument, _argument) && placeholderAt == _placeholderAt) {
      return;
    }
    setState(() {
      _argument = argument;
      _placeholderAt = placeholderAt;
    });
  }

  static bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static RenderEditable? _findEditable(RenderObject? node) {
    if (node == null) return null;
    if (node is RenderEditable) return node;
    RenderEditable? found;
    node.visitChildren((child) => found ??= _findEditable(child));
    return found;
  }

  @override
  Widget build(BuildContext context) {
    // Every rebuild may have moved the text (a width change, a new shape), and
    // measuring is cheap and settles: it only sets state when a box moved.
    _measureSoon();
    final themeState = context.theme;
    final usage = _placeholder(widget.shape?.usage);
    final at = _placeholderAt;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CommandPainter(
                argument: _argument,
                // Recessed into the bar, which is itself `bgTertiary`: in a
                // message row the same box is lighter than the row instead.
                fill: themeState.bgContent,
                border: themeState.borderPrimary,
              ),
            ),
          ),
        ),
        KeyedSubtree(key: _field, child: widget.child),
        if (at != null && usage != null)
          Positioned(
            left: at.dx,
            top: at.dy,
            right: 0,
            child: IgnorePointer(
              child: Text(
                usage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.placeholderStyle.copyWith(
                  color: themeState.textQuaternary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// `<song, artist or link>` reads as code; the placeholder says it
  /// plainly. Brackets are how a usage marks what to type, not part of it.
  static String? _placeholder(String? usage) {
    final plain = usage?.replaceAll(RegExp(r'[<>\[\]]'), '').trim();
    return plain == null || plain.isEmpty ? null : plain;
  }
}

class _CommandPainter extends CustomPainter {
  final List<Rect> argument;
  final Color fill;
  final Color border;

  _CommandPainter({
    required this.argument,
    required this.fill,
    required this.border,
  });

  /// Room around the glyphs, so a box frames its words instead of clipping
  /// them; kept inside the line so two wrapped lines do not overlap.
  static const EdgeInsets _pad = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 1,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()..color = fill;
    final borderPaint = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final rect in argument) {
      if (rect.width <= 0) continue;
      final box = RRect.fromRectAndRadius(
        _pad.inflateRect(rect),
        const Radius.circular(K.radiusRow),
      );
      canvas
        ..drawRRect(box, fillPaint)
        ..drawRRect(box.deflate(0.5), borderPaint);
    }
  }

  @override
  bool shouldRepaint(_CommandPainter old) =>
      old.argument != argument || old.fill != fill || old.border != border;
}
