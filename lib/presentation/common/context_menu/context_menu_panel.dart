import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';

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

  final List<Widget> children;
  final double maxWidth;

  /// The design pins the menu card at 15 — between a card (12) and a panel
  /// (16), which is the register a popover sits in.
  static const double radius = 15;

  const ContextMenuPanel({
    super.key,
    required this.children,
    this.heading,
    this.subheading,
    this.maxWidth = 232,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: themeState.bgElevated,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: themeState.borderElevated),
            boxShadow: AppShadows.popover,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (heading != null) _buildHeading(themeState),
              ...children,
            ],
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
              fontSize: 9.5,
              letterSpacing: 1.3,
              color: themeState.textQuaternary,
            ),
          ),
          if (subheading != null) ...[
            const SizedBox(height: 3),
            Text(
              subheading!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.row.copyWith(color: themeState.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}
