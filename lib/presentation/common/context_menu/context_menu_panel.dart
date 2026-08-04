import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/constants.dart';
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

  const ContextMenuPanel({
    super.key,
    required this.children,
    this.heading,
    this.subheading,
    this.maxWidth = 224,
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
            borderRadius: BorderRadius.circular(K.radiusCard),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            heading!.toUpperCase(),
            style: AppText.sectionLabel.copyWith(
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
