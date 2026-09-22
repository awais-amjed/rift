import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import 'loading_dots.dart';

/// The dots at the end of a paged list while the next page loads — which is
/// also what tells somebody the list has not simply stopped.
class ListLoadingFooter extends StatelessWidget {
  const ListLoadingFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: LoadingDots(color: context.theme.accentBright, dotSize: 5),
      ),
    );
  }
}
