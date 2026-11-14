import 'package:material_ui/material_ui.dart';

import '../../data/constants.dart';
import '../theme/app_motion.dart';

/// The share of a download that is down, as a ring the size of the icon it
/// stands for, moving smoothly between the reports that come several times a
/// second.
class DownloadRing extends StatelessWidget {
  final double fraction;
  final Color color;
  final double size;

  const DownloadRing({
    super.key,
    required this.fraction,
    required this.color,
    this.size = K.iconTiny,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Padding(
        padding: EdgeInsets.all(size / 12),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: fraction),
          duration: AppMotion.state,
          curve: AppMotion.settle,
          builder: (context, value, _) => CircularProgressIndicator(
            value: value,
            strokeWidth: size * 0.14,
            color: color,
            backgroundColor: color.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}
