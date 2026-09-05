import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import 'app_button.dart';

/// "Didn't get the email? Send it again" — and, once asked, the wait until it
/// may be asked again.
///
/// The countdown is here rather than in the cubit because it is the only thing
/// on screen that changes every second, and a cubit emitting at that rate would
/// rebuild the whole backup screen for the sake of two digits. The cubit says
/// *when* (`SupabaseBackupState.resendAvailableAt`); this counts down to it.
///
/// The wait is not a formality. The central project's mail is metered — a
/// minimum gap between two emails to one address, and an hourly cap for the
/// whole project — and a refused request spends the same allowance as an
/// accepted one. Holding the button is cheaper than pressing it and being told.
class ResendConfirmationButton extends StatefulWidget {
  /// When another may be asked for, from the cubit. Null means now.
  final DateTime? availableAt;

  /// Whether a request is in flight.
  final bool isProcessing;

  /// Where "now" comes from. Only ever overridden by tests: the countdown is
  /// the one thing here worth checking, and it cannot be checked against a
  /// clock that `pump` does not move.
  final DateTime Function() clock;

  const ResendConfirmationButton({
    super.key,
    required this.availableAt,
    this.isProcessing = false,
    this.clock = DateTime.now,
  });

  @override
  State<ResendConfirmationButton> createState() =>
      _ResendConfirmationButtonState();
}

class _ResendConfirmationButtonState extends State<ResendConfirmationButton> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(ResendConfirmationButton old) {
    super.didUpdateWidget(old);
    if (old.availableAt != widget.availableAt) _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// One timer only while there is something to count down to, so the widget
  /// costs nothing on the screen it spends most of its life on.
  void _syncTicker() {
    _ticker?.cancel();
    if (_remaining == Duration.zero) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_remaining == Duration.zero) _ticker?.cancel();
    });
  }

  Duration get _remaining {
    final until = widget.availableAt;
    if (until == null) return Duration.zero;
    final left = until.difference(widget.clock());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  Widget build(BuildContext context) {
    final left = _remaining;
    final waiting = left > Duration.zero;

    // It sits in a footer beside Sign in, so it is the same kind of button;
    // while it must wait, the label carries the countdown and the button is
    // disabled, which keeps the footer's shape rather than swapping a
    // sentence in and out of it.
    return AppButton(
      label: waiting ? 'Resend in ${left.inSeconds}s' : 'Resend',
      variant: AppButtonVariant.secondary,
      onPressed: waiting || widget.isProcessing
          ? null
          : context.read<SupabaseBackupCubit>().resendConfirmation,
    );
  }
}
