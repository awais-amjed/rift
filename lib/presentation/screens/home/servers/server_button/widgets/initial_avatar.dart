import 'package:flutter/material.dart';

import '../../../../../theme/custom_colors.dart';

/// Avatar showing the initial letter of a server name.
class InitialAvatar extends StatelessWidget {
  final String name;

  const InitialAvatar({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: CustomColors.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}
