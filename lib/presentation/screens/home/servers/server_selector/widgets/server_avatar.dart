import 'package:flutter/material.dart';

import '../../../../../../../data/classes/server.dart';
import '../../../../../theme/custom_colors.dart';

/// Circular avatar displaying the first letter of a server's name.
class ServerAvatar extends StatelessWidget {
  final Server server;
  final double size;

  const ServerAvatar({super.key, required this.server, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: CustomColors.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        server.name.isNotEmpty ? server.name[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}
