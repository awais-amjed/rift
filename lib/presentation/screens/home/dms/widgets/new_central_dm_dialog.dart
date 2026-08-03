import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';

/// Handle search for starting a central DM.
class NewCentralDmDialog extends StatefulWidget {
  /// Prefills the handle search — used when arriving from a member's
  /// context menu, where their server display name is the best guess at a
  /// handle (central accounts are separate identities, so there is no link).
  final String? initialQuery;

  const NewCentralDmDialog({super.key, this.initialQuery});

  static void show(BuildContext context, {String? initialQuery}) {
    showCustomDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<CentralDmCubit>()),
          BlocProvider.value(value: context.read<DmCubit>()),
        ],
        child: NewCentralDmDialog(initialQuery: initialQuery),
      ),
    );
  }

  @override
  State<NewCentralDmDialog> createState() => _NewCentralDmDialogState();
}

class _NewCentralDmDialogState extends State<NewCentralDmDialog> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<DmConversation> _results = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery;
    if (query != null && query.trim().isNotEmpty) {
      _controller.text = query.trim();
      // Run the search straight away — the point of arriving prefilled is not
      // having to retype it.
      _onChanged(_controller.text);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final results = await context.read<CentralDmCubit>().searchHandles(value);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return AppModal(
      title: 'Find someone',
      subtitle: 'Search the central directory by handle.',
      content: SizedBox(
        width: 380,
        height: 300,
        child: Column(
          children: [
            AppTextField(
              controller: _controller,
              hint: 'handle',
              autofocus: true,
              onChanged: _onChanged,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        for (final result in _results)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              hoverColor: themeState.bgHover,
                              onTap: () {
                                context.read<DmCubit>().closeConversation();
                                context.read<CentralDmCubit>().openConversation(
                                  peerId: result.peerId,
                                  peerHandle: result.peerName,
                                  peerChatKey: result.peerChatPublicKey,
                                  peerSigningKey: result.peerSigningPublicKey,
                                );
                                Navigator.of(context).pop();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.public,
                                      size: 18,
                                      color: themeState.textTertiary,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '@${result.peerName}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: themeState.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
