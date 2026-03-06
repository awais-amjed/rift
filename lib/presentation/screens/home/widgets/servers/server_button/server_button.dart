import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import 'widgets/server_avatar.dart';

/// Displays the currently selected server in the sidebar header.
class ServerButton extends StatelessWidget {
  final Server server;
  final VoidCallback onTap;

  const ServerButton({super.key, required this.server, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: themeState.bgHover,
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: themeState.borderPrimary),
                ),
              ),
              child: Row(
                children: [
                  ServerAvatar(server: server),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      server.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: themeState.textPrimary,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
