import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';
import 'centered_scroll_view.dart';
import 'loading_dots.dart';

/// What a list shows when it has nothing in it.
///
/// Deliberately *not* a [HintCard]. A bordered grey box is right for a note
/// sitting beside content — it marks itself as an aside. Given the whole body
/// of a panel it reads as a broken row: a filled rectangle where the filled
/// rectangles usually are, except empty. This keeps the same canvas the rows
/// sit on and puts a small tinted glyph, a title and one line in the middle of
/// it, so an empty tab looks like a place with nothing in it yet rather than a
/// place that failed to load.
///
/// Centred rather than parked at the top for the same reason: content stacks
/// from the top, so anything up there is read as the first item of a list.
///
/// The same recipe serves the voice stage's waiting, connecting and failed
/// states — a 46px tinted glyph, a 15px title, a 12px line — so an empty
/// panel and a failed join read as the same kind of moment rather than four
/// hand-rolled columns at four sizes.
class EmptyState extends StatelessWidget {
  final IconData icon;

  /// Something is happening: the glyph gives way to the loading dots.
  final bool busy;

  /// The raw cause, kept under the sentence that interprets it, so a bug
  /// report still carries what actually happened. Mono, legible, and cut to
  /// two lines — the useful part of an exception is at its start.
  final String? detail;

  /// Three or four words. The state, not an instruction.
  final String title;

  /// One sentence under it — what will end up here, or how to put something
  /// here. Null when the title already says everything.
  final String? message;

  /// Optional call to action beneath the text.
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.detail,
    this.action,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return CenteredScrollView(
      // Not quite centred: the extra room at the bottom lifts the block a
      // little above the middle, where the eye already is after reading the
      // tabs. Dead-centre in a tall panel reads as low.
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 76),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              // Tinted with the palette rather than filled with grey: the
              // one spot of colour is what stops the middle of an empty
              // panel from looking unpainted.
              color: themeState.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(K.radiusCard),
            ),
            child: busy
                ? Center(
                    child: LoadingDots(
                      color: themeState.accentBright,
                      dotSize: 6,
                    ),
                  )
                : Icon(icon, size: 21, color: themeState.accentBright),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.sectionTitle.copyWith(
              color: themeState.textSecondary,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              // Long enough for a sentence, short enough that the eye does
              // not have to travel back across a wide panel to find the
              // next line.
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: AppText.secondary.copyWith(
                  height: 1.55,
                  color: themeState.textTertiary,
                ),
              ),
            ),
          ],
          if (detail != null) ...[
            const SizedBox(height: 14),
            Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: themeState.bgPrimary,
                borderRadius: BorderRadius.circular(K.radiusRow),
                border: Border.all(color: themeState.borderPrimary),
              ),
              child: Text(
                detail!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.code.copyWith(color: themeState.textSecondary),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
