import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/app_text.dart';

/// One labelled block of credentials in the create-server form — the heading
/// rule and the fields under it.
///
/// Supabase and LiveKit differ only by their name and their fields, so they
/// are one widget taking parameters rather than two near-identical stretches
/// of the form.
class CredentialGroup extends StatelessWidget {
  final String label;

  /// The fields, in order. The spacing between them is this widget's business.
  final List<Widget> fields;

  /// Gap between fields, and between the heading and the first one.
  static const _gap = 12.0;

  const CredentialGroup({super.key, required this.label, required this.fields});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppText.sectionLabel.copyWith(
                    color: themeState.textTertiary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Divider(color: themeState.borderPrimary, height: 1),
                ),
              ],
            ),
            for (final field in fields) ...[
              const SizedBox(height: _gap),
              field,
            ],
          ],
        );
      },
    );
  }
}
