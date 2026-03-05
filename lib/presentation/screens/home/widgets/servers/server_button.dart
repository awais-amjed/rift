import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

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
                  _ServerAvatar(server: server),
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

class _ServerAvatar extends StatelessWidget {
  final Server server;

  const _ServerAvatar({required this.server});

  @override
  Widget build(BuildContext context) {
    if (server.iconUrl != null && server.iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9999),
        child: CachedNetworkImage(
          imageUrl: server.iconUrl!,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _InitialAvatar(name: server.name),
        ),
      );
    }
    return _InitialAvatar(name: server.name);
  }
}

class _InitialAvatar extends StatelessWidget {
  final String name;

  const _InitialAvatar({required this.name});

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

/// Placeholder shown when no server is selected.
class NoServerButton extends StatelessWidget {
  final VoidCallback onTap;

  const NoServerButton({super.key, required this.onTap});

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
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: themeState.bgTertiary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.dns_outlined,
                      size: 16,
                      color: themeState.textQuaternary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No Server Selected',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: themeState.textTertiary,
                          ),
                        ),
                        Text(
                          'Click to add',
                          style: TextStyle(
                            fontSize: 11,
                            color: themeState.textQuaternary,
                          ),
                        ),
                      ],
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
