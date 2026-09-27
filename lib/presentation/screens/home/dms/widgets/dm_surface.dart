import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// The two-column layout a DM surface uses: conversation list on the chrome
/// surface, the open conversation on the content surface.
///
/// The same split as the sidebar and chat panel outside it, one level in —
/// which is what keeps a DM surface reading as part of the app rather than a
/// screen of its own.
///
/// A phone has no room for one column inside another: 280px of list against a
/// 393px screen left the conversation a gutter to live in. So only the list is
/// drawn there, and an open conversation is a page the phone shell pushes over
/// it. There is no "pick a conversation" panel in that mode because you would
/// be reading it instead of the list it is telling you to use. A panel too
/// narrow for both on a desktop does the same, without the page.
class DmSurface extends StatelessWidget {
  final Widget list;

  /// The open conversation, or null for the resting state.
  final Widget? conversation;

  /// Shown when nothing is open. Wide layouts only — see the class comment.
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;

  /// The list folded away so the conversation has the whole surface — a DM
  /// call someone expanded.
  final bool listHidden;

  static const double listWidth = 280;

  /// The narrowest the open conversation may be beside the list. Below it the
  /// two take turns, as on a phone — see [build].
  static const double minConversationWidth = 320;

  const DmSurface({
    super.key,
    required this.list,
    required this.emptyTitle,
    required this.emptyMessage,
    this.conversation,
    this.emptyIcon = Icons.forum_outlined,
    this.listHidden = false,
  });

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact) return list;

    final themeState = context.theme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The layout mode follows the window, not this panel. A narrow
        // desktop window with the sidebar open is not compact, and left the
        // conversation a few dozen pixels beside the list, its text wrapping
        // a letter to a line. Short of room for both, the two take turns:
        // the conversation while one is open — its close button goes back —
        // and the list otherwise.
        if (constraints.maxWidth < listWidth + minConversationWidth) {
          return conversation ?? list;
        }
        final open = conversation;
        if (listHidden && open != null) return open;
        return DmListBeside(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: themeState.bgSecondary,
                child: SizedBox(width: listWidth, child: list),
              ),
              Container(width: 1, color: themeState.borderPrimary),
              Expanded(child: conversation ?? _buildEmpty(themeState)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty(ThemeState themeState) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(emptyIcon, size: 44, color: themeState.textQuaternary),
          const SizedBox(height: 12),
          Text(
            emptyTitle,
            style: AppText.sectionTitle.copyWith(color: themeState.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: themeState.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Set over a conversation that has its list beside it.
///
/// The list's header carries the button that brings a hidden sidebar back.
/// A conversation alone — on Home, where the list is the sidebar itself, or
/// in a window too narrow for both — has to carry it in its own header, or a
/// hidden sidebar has no way back from there.
class DmListBeside extends InheritedWidget {
  const DmListBeside({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DmListBeside>() != null;

  @override
  bool updateShouldNotify(DmListBeside old) => false;
}
