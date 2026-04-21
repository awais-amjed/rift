import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

class CopyableField extends StatelessWidget {
  final String? value;
  final String? placeholder;
  final bool copied;
  final VoidCallback? onCopy;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  final Color? placeholderColor;

  const CopyableField({
    super.key,
    this.value,
    this.placeholder,
    required this.copied,
    this.onCopy,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
    this.placeholderColor,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: value != null
                    ? Text(
                        value!,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: textColor,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : Text(
                        placeholder ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: placeholderColor ?? textColor,
                        ),
                      ),
              ),
              if (onCopy != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    hoverColor: themeState.bgHover,
                    onTap: onCopy,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        copied ? Icons.check : Icons.copy,
                        size: 15,
                        color: copied ? CustomColors.success : textColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
