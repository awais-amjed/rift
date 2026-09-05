import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../theme/app_text.dart';

/// The "Jump to…" pill under the server header — the entry point to the quick
/// switcher.
///
/// It looks like a search field but is a button: the field itself lives in the
/// switcher, so there is only one place that owns the query.
class JumpField extends StatelessWidget {
  final VoidCallback onTap;

  const JumpField({super.key, required this.onTap});

  /// The modifier is named for the platform the user is actually on —
  /// showing ⌘ on Linux would just be wrong.
  static String get shortcutLabel =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘K' : 'Ctrl K';

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
          child: Material(
            color: themeState.bgHover,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              hoverColor: themeState.bgActive,
              onTap: onTap,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: themeState.borderPrimary),
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 15,
                      color: themeState.textQuaternary,
                    ),
                    Expanded(
                      child: Text(
                        'Jump to…',
                        style: AppText.secondary.copyWith(
                          color: themeState.textQuaternary,
                        ),
                      ),
                    ),
                    // A phone has no Ctrl key to press, so the chip is
                    // instructions for a keyboard that isn't there — and the
                    // width it takes is width the field wanted.
                    if (!HostPlatform.isMobile) _buildKbdChip(themeState),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildKbdChip(ThemeState themeState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: themeState.bgActive,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        shortcutLabel,
        style: AppText.kbd.copyWith(color: themeState.textQuaternary),
      ),
    );
  }
}
