import 'package:flutter/material.dart';

import '../../../data/constants.dart';
import '../../common/app_toast_close.dart';
import '../../common/user_avatar.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../theme/theme_context.dart';

/// A message arriving in a focused window: who sent it and where, in a card
/// at the top middle of the window, opening the conversation when pressed.
///
/// Not a toast. A toast in the corner reports on something the person did; this
/// is somebody reaching them, so it carries the sender's face where a toast has
/// a status icon, and sits where the eye already is.
class InAppMessageBanner extends StatefulWidget {
  /// The widest it gets, which is the column toasts are laid out in.
  static const double maxWidth = 360;

  static const double _avatar = 36;

  final String? senderId;
  final String sender;
  final String? avatarPath;
  final String what;
  final String? place;

  /// Draws the corner of the picture: an at sign for a mention, otherwise a
  /// speech bubble.
  final bool isMention;

  final VoidCallback onTap;
  final VoidCallback onClose;

  /// Told when the mouse comes onto it and leaves, to hold it still meanwhile.
  final ValueChanged<bool>? onHover;

  const InAppMessageBanner({
    super.key,
    required this.senderId,
    required this.sender,
    required this.avatarPath,
    required this.what,
    required this.place,
    required this.isMention,
    required this.onTap,
    required this.onClose,
    this.onHover,
  });

  @override
  State<InAppMessageBanner> createState() => _InAppMessageBannerState();
}

class _InAppMessageBannerState extends State<InAppMessageBanner> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    setState(() => _hovered = hovered);
    widget.onHover?.call(hovered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final shape = BorderRadius.circular(K.radiusCard);
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: InAppMessageBanner.maxWidth,
          ),
          // Up is the way it came, and a phone has no hover to close it with.
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < 0) widget.onClose();
            },
            child: Container(
              decoration: BoxDecoration(
                color: theme.bgElevated,
                borderRadius: shape,
                border: Border.all(color: theme.primary.withValues(alpha: 0.4)),
                boxShadow: AppShadows.popover,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: shape,
                child: InkWell(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  borderRadius: shape,
                  hoverColor: theme.bgHoverSubtle,
                  onTap: widget.onTap,
                  onHover: _setHovered,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _picture(),
                        const SizedBox(width: 12),
                        Flexible(child: _words()),
                        const SizedBox(width: 16),
                        // Its room is kept, so the card does not change
                        // width under the pointer.
                        IgnorePointer(
                          ignoring: !_hovered,
                          child: AnimatedOpacity(
                            opacity: _hovered ? 1 : 0,
                            duration: AppMotion.react,
                            curve: AppMotion.settle,
                            child: AppToastClose(onTap: widget.onClose),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _picture() => Stack(
    clipBehavior: Clip.none,
    children: [
      UserAvatar(
        avatarPath: widget.avatarPath,
        name: widget.sender,
        seed: widget.senderId,
        size: InAppMessageBanner._avatar,
      ),
      Positioned(
        right: -4,
        bottom: -4,
        child: _Kind(isMention: widget.isMention),
      ),
    ],
  );

  Widget _words() {
    final theme = context.theme;
    final place = widget.place;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: widget.sender,
                style: AppText.strong.copyWith(color: theme.textPrimary),
              ),
              if (place != null)
                TextSpan(
                  text: '  $place',
                  style: AppText.meta.copyWith(color: theme.textTertiary),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          widget.what,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.row.copyWith(color: theme.textSecondary),
        ),
      ],
    );
  }
}

/// The accent dot on the picture's corner, saying what kind of message it is.
class _Kind extends StatelessWidget {
  final bool isMention;

  const _Kind({required this.isMention});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: theme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: theme.bgElevated, width: 2),
      ),
      child: Icon(
        isMention ? Icons.alternate_email_rounded : Icons.chat_bubble_rounded,
        size: 9,
        color: theme.onPrimary,
      ),
    );
  }
}
