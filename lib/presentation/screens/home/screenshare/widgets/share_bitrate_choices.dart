import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../data/classes/server_limits.dart';
import '../../../../../data/constants.dart';
import '../../../../common/context_menu/text_field_context_menu.dart';
import '../../../../common/tap_to_focus.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../sections/bitrate_section.dart';
import 'share_choice_button.dart';
import 'share_choice_grid.dart';

/// The share's bitrate: Auto, the usual numbers, and a box for any other.
///
/// Typing lets go of the buttons and pressing one empties the box, so one thing
/// is ever selected; an empty box is Auto again. It keeps what is being typed
/// as its own state, because the setting alone cannot tell: on the way to 100,
/// the 10 is a number there is a button for, and lighting that button would
/// take the box away from under the caret.
///
/// [maxMbps] is what this server allows. A button over it is greyed, and a
/// number typed over it is held to it, as [BitrateSection.effectiveFor] holds
/// any choice.
class ShareBitrateChoices extends StatefulWidget {
  /// The bitrate picked by hand, or null for Auto.
  final int? chosen;

  /// What Auto sends for this picture, already held to [maxMbps].
  final int auto;
  final int maxMbps;

  /// Null is Auto.
  final ValueChanged<int?> onChanged;

  const ShareBitrateChoices({
    super.key,
    required this.chosen,
    required this.auto,
    required this.onChanged,
    this.maxMbps = ServerLimits.unlimited,
  });

  /// The buttons. Anything else goes in the box.
  static const choices = [2, 4, 6, 8, 10, 15, 20, 30, 50];

  /// The most the box takes, which is the most the picker has ever offered.
  static const maxTyped = 100;

  @override
  State<ShareBitrateChoices> createState() => _ShareBitrateChoicesState();
}

class _ShareBitrateChoicesState extends State<ShareBitrateChoices> {
  final _focus = FocusNode();
  late final TextEditingController _typed;

  int? get _sent {
    final chosen = widget.chosen;
    return chosen == null
        ? null
        : BitrateSection.effectiveFor(chosen, widget.maxMbps);
  }

  bool get _typing => (int.tryParse(_typed.text) ?? 0) > 0;

  bool _allowed(int mbps) =>
      widget.maxMbps == ServerLimits.unlimited || mbps <= widget.maxMbps;

  @override
  void initState() {
    super.initState();
    final sent = _sent;
    _typed = TextEditingController(
      text: sent == null || ShareBitrateChoices.choices.contains(sent)
          ? ''
          : '$sent',
    );
  }

  @override
  void dispose() {
    _typed.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTyped(String text) {
    setState(() {});
    final mbps = int.tryParse(text) ?? 0;
    widget.onChanged(mbps > 0 ? mbps : null);
  }

  void _pressed(int? mbps) {
    _typed.clear();
    _focus.unfocus();
    setState(() {});
    widget.onChanged(mbps);
  }

  static String _capTyped(String text) {
    final mbps = int.tryParse(text);
    return mbps != null && mbps > ShareBitrateChoices.maxTyped
        ? '${ShareBitrateChoices.maxTyped}'
        : text;
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sent;
    return ShareChoiceGrid(
      columns: 6,
      minWidth: 74,
      lastSpan: 2,
      children: [
        ShareChoiceButton(
          label: 'Auto',
          sub: '${widget.auto} Mbps',
          selected: !_typing && sent == null,
          onTap: () => _pressed(null),
        ),
        for (final mbps in ShareBitrateChoices.choices)
          ShareChoiceButton(
            label: '$mbps Mbps',
            selected: !_typing && sent == mbps,
            onTap: _allowed(mbps) ? () => _pressed(mbps) : null,
          ),
        _box(context),
      ],
    );
  }

  Widget _box(BuildContext context) {
    final theme = context.theme;
    return TapToFocus(
      focusNode: _focus,
      child: ListenableBuilder(
        listenable: _focus,
        builder: (context, field) => Container(
          height: K.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _typing ? theme.channelActiveBg : theme.bgTertiary,
            borderRadius: BorderRadius.circular(K.radiusRow),
            border: Border.all(
              color: _typing || _focus.hasFocus
                  ? theme.channelActiveBorder
                  : theme.borderElevated,
            ),
          ),
          child: field,
        ),
        child: Row(
          spacing: 6,
          children: [
            Expanded(
              child: TextField(
                contextMenuBuilder: TextFieldContextMenu.builder,
                controller: _typed,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction(
                    (_, next) => next.copyWith(
                      text: _capTyped(next.text),
                      selection: TextSelection.collapsed(
                        offset: _capTyped(next.text).length,
                      ),
                    ),
                  ),
                ],
                onChanged: _onTyped,
                style: AppText.rowQuiet.copyWith(color: theme.textPrimary),
                // The box above is the field; the theme's outline would draw a
                // second one inside it.
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Custom',
                  hintStyle: AppText.rowQuiet.copyWith(
                    color: theme.textTertiary,
                  ),
                ),
              ),
            ),
            Text(
              'Mbps',
              style: AppText.secondary.copyWith(color: theme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
