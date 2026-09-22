import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../data/enums/sensitive_content_mode.dart';
import '../../../theme/app_text.dart';
import '../../../theme/media_colors.dart';

/// A flagged image behind frosted glass, with the reason and the way through.
///
/// The picture is drawn and blurred rather than replaced by a box, so the
/// cover has the image's own shape and colour: what is hidden is still
/// recognisably a photograph, and the reader can tell a covered attachment
/// from a broken one. In [SensitiveContentMode.blur] a tap lifts it, and the
/// choice is remembered for the session so a scroll does not re-cover a
/// picture already looked at. In [SensitiveContentMode.hide] there is no way
/// through here; the setting is where that is changed.
class SensitiveImageCover extends StatefulWidget {
  final String attachmentId;
  final SensitiveContentMode mode;
  final Widget child;

  const SensitiveImageCover({
    super.key,
    required this.attachmentId,
    required this.mode,
    required this.child,
  });

  /// Attachments revealed this session. Static on purpose: a thumbnail's
  /// state is rebuilt every time it scrolls into view, and the decision to
  /// look belongs to the picture, not to the widget that happened to draw it.
  static final Set<String> _revealed = {};

  static const double _sigma = 24;

  /// For tests: forget every reveal.
  @visibleForTesting
  static void resetReveals() => _revealed.clear();

  @override
  State<SensitiveImageCover> createState() => _SensitiveImageCoverState();
}

class _SensitiveImageCoverState extends State<SensitiveImageCover> {
  bool get _revealed =>
      SensitiveImageCover._revealed.contains(widget.attachmentId);

  bool get _canReveal => widget.mode == SensitiveContentMode.blur;

  void _reveal() {
    if (!_canReveal) return;
    setState(() => SensitiveImageCover._revealed.add(widget.attachmentId));
  }

  @override
  Widget build(BuildContext context) {
    if (_revealed) return widget.child;
    return MouseRegion(
      cursor: _canReveal ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: _canReveal ? _reveal : null,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: SensitiveImageCover._sigma,
                sigmaY: SensitiveImageCover._sigma,
                tileMode: TileMode.decal,
              ),
              child: widget.child,
            ),
            Positioned.fill(
              child: ColoredBox(
                color: MediaColors.veil,
                // Scaled down rather than overflowing: a sticker-sized
                // thumbnail still gets the icon and a legible word or two.
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        const Icon(
                          Icons.visibility_off_outlined,
                          size: 20,
                          color: MediaColors.onMedia,
                        ),
                        Text(
                          'Sensitive image',
                          style: AppText.secondaryStrong.copyWith(
                            color: MediaColors.onMedia,
                          ),
                        ),
                        Text(
                          _canReveal
                              ? 'Tap to show'
                              : 'Hidden by your settings',
                          style: AppText.meta.copyWith(
                            color: MediaColors.onMediaSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
