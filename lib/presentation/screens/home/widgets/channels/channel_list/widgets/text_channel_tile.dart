import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';

/// Tile for displaying a text channel.
class TextChannelTile extends StatelessWidget {
  final Channel channel;

  const TextChannelTile({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: themeState.bgHover,
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.tag, size: 17, color: themeState.textQuaternary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      channel.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: themeState.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
