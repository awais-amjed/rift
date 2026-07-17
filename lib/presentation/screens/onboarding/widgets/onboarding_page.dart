import 'package:flutter/material.dart';

/// Shared layout for every onboarding page: content is vertically centered
/// while the window is tall enough, and becomes scrollable (instead of
/// clipping) when the window is short.
class OnboardingPage extends StatelessWidget {
  final Widget child;

  const OnboardingPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 32,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
