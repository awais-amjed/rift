import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/server.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';

/// Circular avatar displaying the first letter of a server's name.
class ServerAvatar extends StatelessWidget {
  final Server server;
  final double size;

  const ServerAvatar({super.key, required this.server, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeCubit>().state;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.primary, theme.gradientPartner],
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        server.name.isNotEmpty ? server.name[0].toUpperCase() : '?',
        style: TextStyle(
          color: theme.onPrimary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}
