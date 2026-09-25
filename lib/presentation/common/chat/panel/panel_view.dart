import 'package:flutter/material.dart';

import '../../../../data/classes/panel_block.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../link_preview_card.dart';
import 'panel_actions.dart';
import 'panel_fields.dart';

/// A bot's panel, drawn with Rift's own widgets from a fixed vocabulary.
///
/// The bot supplies structure and never a pixel. Everything here is Rift's
/// theme, so a panel keeps working when the accent palette changes and looks
/// the same on a phone as on a desktop — and, more to the point, cannot be made
/// to look like part of the app's own chrome.
///
/// Unknown block types are already gone by the time this runs: [Panel.tryParse]
/// drops them. A panel from a bot built against a newer vocabulary loses the
/// blocks this client does not have and keeps the rest, rather than failing
/// whole.
class PanelView extends StatelessWidget {
  final Panel panel;

  /// Null while a press is in flight, or where the viewer cannot press —
  /// a panel is still worth reading when you cannot touch it.
  final void Function(String action, String? value)? onAction;

  const PanelView({super.key, required this.panel, this.onAction});

  /// Only words: nothing to press, fill in or read off a bar.
  bool get _wordsOnly => panel.blocks.every(
    (b) => b.type == PanelBlockType.heading || b.type == PanelBlockType.text,
  );

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // A reply that is only words is drawn as words. In a frame, "Stopped" was
    // a bordered box the height of a button with nothing to press in it. The
    // message's own badge already says a bot wrote it; the frame is for a
    // panel with controls, where it keeps them from passing for the app's.
    if (_wordsOnly) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [for (final block in panel.blocks) _block(context, block)],
        ),
      );
    }
    // Bounded, and no wider than its content. A panel used to take the whole
    // chat column whatever it held, so a bot answering "Stopped" got a
    // bordered card three quarters of the screen wide around one word, which
    // reads as a rendering fault rather than a reply. The same width as a
    // link preview, because they are the same kind of thing: a bounded card
    // inside a message.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LinkPreviewCard.maxWidth),
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: themeState.bgSecondary,
            borderRadius: BorderRadius.circular(K.radiusRow),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final block in panel.blocks) _block(context, block),
            ],
          ),
        ),
      ),
    );
  }

  Widget _block(BuildContext context, PanelBlock block) {
    final themeState = context.theme;
    return switch (block.type) {
      PanelBlockType.heading => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          block.text!,
          style: AppText.row.copyWith(
            color: themeState.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      PanelBlockType.text => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          block.text!,
          style: AppText.secondary.copyWith(
            color: themeState.textSecondary,
            height: 1.4,
          ),
        ),
      ),
      PanelBlockType.fields => PanelFields(fields: block.fields),
      PanelBlockType.progress => _progress(context, block),
      PanelBlockType.divider => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Divider(height: 1, color: themeState.borderPrimary),
      ),
      PanelBlockType.actions ||
      PanelBlockType.select => PanelActions(block: block, onAction: onAction),
      // Dropped in parsing; the switch is exhaustive so the compiler says so if
      // a type is ever added without a widget to draw it.
      PanelBlockType.unknown => const SizedBox.shrink(),
    };
  }

  Widget _progress(BuildContext context, PanelBlock block) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(K.radiusPill),
            child: LinearProgressIndicator(
              value: block.value,
              minHeight: 5,
              backgroundColor: themeState.bgHover,
              valueColor: AlwaysStoppedAnimation(themeState.accentBright),
            ),
          ),
          if ((block.text ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              block.text!,
              style: AppText.meta.copyWith(color: themeState.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
