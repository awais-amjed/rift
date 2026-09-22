import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../theme/app_text.dart';
import '../popover_surface.dart';
import 'context_menu_sheet.dart';

/// The floating card a context menu's rows sit in.
///
/// Elevated surface plus a real shadow, because a menu that only differed
/// from the panel behind it by a hairline border would read as part of the
/// layout rather than something opened on top of it.
class ContextMenuPanel extends StatelessWidget {
  /// Small uppercase label above the items — MEMBER, SERVER.
  final String? heading;

  /// Second line under [heading], usually the subject's name.
  final String? subheading;

  /// Sits beside [subheading] — the subject's avatar or server icon, so the
  /// menu says *which* one it belongs to at a glance.
  final Widget? leading;

  /// A third, quieter line — a server's host, a member's handle.
  final String? caption;

  final List<Widget> children;
  final double maxWidth;

  const ContextMenuPanel({
    super.key,
    required this.children,
    this.heading,
    this.subheading,
    this.leading,
    this.caption,
    this.maxWidth = 232,
  });

  @override
  Widget build(BuildContext context) {
    final sheet = ContextMenuPresentation.of(context);
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        // In a sheet the sheet is the surface: full width, no card of its own,
        // and a rule under the heading because there is no card edge to end
        // the heading against.
        if (sheet != null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (heading != null) ...[
                  Row(
                    children: [
                      if (sheet.popSubmenu != null)
                        IconButton(
                          tooltip: 'Back',
                          onPressed: sheet.popSubmenu,
                          icon: Icon(
                            Icons.chevron_left_rounded,
                            size: 26,
                            color: themeState.textSecondary,
                          ),
                        ),
                      Expanded(child: _buildHeading(themeState)),
                    ],
                  ),
                  Divider(height: 9, color: themeState.borderPrimary),
                ],
                ...children,
              ],
            ),
          );
        }
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: PopoverSurface(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (heading != null) _buildHeading(themeState),
                ...children,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeading(ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            heading!.toUpperCase(),
            style: AppText.sectionLabel.copyWith(
              color: themeState.textTertiary,
            ),
          ),
          if (subheading != null) ...[
            const SizedBox(height: 5),
            Row(
              spacing: 8,
              children: [
                ?leading,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subheading!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.row.copyWith(
                          color: themeState.textPrimary,
                        ),
                      ),
                      if (caption != null)
                        Text(
                          caption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.meta.copyWith(
                            color: themeState.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
