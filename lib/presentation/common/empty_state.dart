import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';

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
class EmptyState extends StatelessWidget {
  final IconData icon;

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
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return Center(
      child: SingleChildScrollView(
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
              child: Icon(icon, size: 21, color: themeState.accentBright),
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
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}
