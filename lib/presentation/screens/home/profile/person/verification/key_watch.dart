import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';

/// Records [chatKey] as [person]'s key whenever it is shown here — see
/// `SeenKey`. Wraps a surface that seals to or shows somebody's key, so a
/// change is noticed where it happens rather than only in a profile.
///
/// After the frame, not during it: the record is app state, and emitting it
/// mid-build would rebuild the very widgets being built.
class KeyWatch extends StatefulWidget {
  /// `<tier>:<their id>` — see `AppState.verifiedCodes`. Null watches nobody.
  final String? person;

  /// Their key as this surface has it. Null — not published, or not fetched
  /// yet — is not a change, and records nothing.
  final String? chatKey;

  final Widget child;

  const KeyWatch({
    super.key,
    required this.person,
    required this.chatKey,
    required this.child,
  });

  @override
  State<KeyWatch> createState() => _KeyWatchState();
}

class _KeyWatchState extends State<KeyWatch> {
  @override
  void initState() {
    super.initState();
    _note();
  }

  @override
  void didUpdateWidget(KeyWatch old) {
    super.didUpdateWidget(old);
    if (old.person != widget.person || old.chatKey != widget.chatKey) _note();
  }

  void _note() {
    final person = widget.person;
    final key = widget.chatKey;
    if (person == null || key == null || key.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppCubit>().noteChatKey(person, key);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
