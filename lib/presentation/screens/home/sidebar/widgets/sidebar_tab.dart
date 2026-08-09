import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';

/// The tab on the left edge that opens the unpinned sidebar.
///
/// A real button, not a hot zone. The sidebar used to slide out on hover,
/// which meant brushing the left edge on the way anywhere flung a 346px panel
/// over your content — and it retracted on the first pixel out, so a menu
/// opened from inside it took the pointer away and the sidebar vanished from
/// under the menu. Nothing here happens unless you click it.
class SidebarTab extends StatefulWidget {
  final VoidCallback onTap;

  const SidebarTab({super.key, required this.onTap});

  @override
  State<SidebarTab> createState() => _SidebarTabState();
}

class _SidebarTabState extends State<SidebarTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Tooltip(
          message: 'Show sidebar',
          waitDuration: const Duration(milliseconds: 400),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                // Grows a little under the pointer, which is the only thing
                // hover does now — it says the tab is pressable, rather than
                // acting on its own.
                width: _hovered ? 22 : 18,
                height: 72,
                decoration: BoxDecoration(
                  color: _hovered
                      ? themeState.bgTertiary
                      : themeState.bgSecondary,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(9),
                    bottomRight: Radius.circular(9),
                  ),
                  border: Border.all(color: themeState.borderPrimary),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: themeState.isDarkTheme ? 0.3 : 0.1,
                      ),
                      blurRadius: 8,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: _hovered
                      ? themeState.textPrimary
                      : themeState.textTertiary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
