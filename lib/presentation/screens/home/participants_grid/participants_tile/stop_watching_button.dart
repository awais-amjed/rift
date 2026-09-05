import 'package:flutter/material.dart';
import '../../../../theme/app_text.dart';

/// Button to stop watching a screenshare stream
class StopWatchingButton extends StatelessWidget {
  final VoidCallback onTap;

  const StopWatchingButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stop_circle, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Stop Watching',
                style: AppText.row.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
