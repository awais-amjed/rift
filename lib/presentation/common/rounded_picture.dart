import 'package:material_ui/material_ui.dart';

/// A picture cut to a rounded square: every avatar and icon picture.
///
/// Painted as a [DecorationImage] with a border radius, not as an [Image]
/// in a [ClipRRect]. On the owner's AMD PC under Linux (Flutter 3.50,
/// Impeller GLES, GNOME on Wayland) picture avatars in a clip flickered
/// between square and rounded corners on every frame, and the same picture
/// as a rounded decoration did not (Nov 14 2026). Flutter's own advice is
/// the same: round a box with `borderRadius` rather than a clip. The
/// scaling is unchanged, since both draw through `paintImage`, mipmapped.
///
/// A decoration on its own drops the old picture the moment the image
/// changes, and needs something under it while the new one decodes, which
/// shows through any clear parts of the picture. So this resolves the
/// picture itself: it keeps drawing the last picture that decoded until the
/// next one has, and draws [fallback] only while there is none.
///
/// Other rounded pictures (chat attachments, link previews) are still
/// clipped: none was ever seen flickering, and [Image] sizes itself from a
/// picture, which a decoration cannot.
class RoundedPicture extends StatefulWidget {
  final ImageProvider image;
  final double size;
  final double radius;

  /// Drawn until the picture is decoded, and instead of it if it fails.
  final Widget? fallback;

  const RoundedPicture({
    super.key,
    required this.image,
    required this.size,
    required this.radius,
    this.fallback,
  });

  @override
  State<RoundedPicture> createState() => _RoundedPictureState();
}

class _RoundedPictureState extends State<RoundedPicture> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// The last picture that decoded, or null while there is none.
  ImageProvider? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(RoundedPicture old) {
    super.didUpdateWidget(old);
    if (widget.image != old.image) _resolve();
  }

  /// Listens for [RoundedPicture.image]. The listener also keeps the
  /// picture live in the image cache, so the decoration finds it decoded
  /// and paints it in the same frame it switches to it.
  void _resolve() {
    final image = widget.image;
    final stream = image.resolve(
      createLocalImageConfiguration(context, size: Size.square(widget.size)),
    );
    if (stream.key == _stream?.key) return;
    _stop();
    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        if (!mounted || _shown == image) return;
        setState(() => _shown = image);
      },
      onError: (_, _) {
        if (!mounted) return;
        setState(() => _shown = null);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _stop() {
    if (_listener case final listener?) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) {
      return widget.fallback ?? SizedBox.square(dimension: widget.size);
    }
    return SizedBox.square(
      dimension: widget.size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          image: DecorationImage(
            image: shown,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
