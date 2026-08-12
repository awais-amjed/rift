import 'package:flutter/widgets.dart';

import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/services/limit_input.dart';

/// The three limit fields of the server settings dialog, as one object.
///
/// They are grouped rather than sitting loose in the dialog's state because
/// they share all of their behaviour: each is seeded from a [ServerLimits],
/// each renders "no limit" as an empty box, and each has to be read back and
/// validated together before anything is sent. Keeping that in one place is
/// also what keeps the dialog itself inside its size budget.
class ServerLimitsControllers {
  /// Bytes on the wire, megabytes in the box — nobody sets an attachment cap
  /// in bytes.
  final attachmentMb = TextEditingController();

  final retentionDays = TextEditingController();
  final historyCap = TextEditingController();

  /// The DM overrides as last seeded. This dialog doesn't show them — they are
  /// set by right-clicking Server DMs — but [ServerLimits] travels whole, so
  /// saving here would send them as null and quietly undo them. Carried rather
  /// than displayed.
  int? _dmRetentionDays;
  int? _dmHistoryCap;

  /// Fill the fields from what the server currently reports.
  void seed(ServerLimits limits) {
    attachmentMb.text = LimitInput.megabytesOf(limits.maxAttachmentBytes);
    retentionDays.text = LimitInput.textOf(limits.messageRetentionDays);
    historyCap.text = LimitInput.textOf(limits.messageHistoryCap);
    _dmRetentionDays = limits.dmRetentionDays;
    _dmHistoryCap = limits.dmHistoryCap;
  }

  void dispose() {
    attachmentMb.dispose();
    retentionDays.dispose();
    historyCap.dispose();
  }

  /// The limits as typed, or the sentence explaining why they aren't valid.
  ///
  /// A blank count means [ServerLimits.unlimited] — that is what an empty box
  /// says to a reader, and it matches how the fields are seeded. The size cap
  /// is the exception: it cannot be blank and it cannot be zero, because a
  /// size has no "off" and a cap of nothing would forbid every attachment.
  ({ServerLimits? limits, String? error}) read() {
    final bytes = LimitInput.parseMegabytes(attachmentMb.text);
    if (bytes == null) {
      return (limits: null, error: 'Set a maximum attachment size.');
    }
    if (bytes == LimitInput.invalid) {
      return (
        limits: null,
        error: 'Maximum attachment size must be at least 1 MB.',
      );
    }
    if (bytes > ServerLimits.maxAttachmentCeiling) {
      final ceiling =
          ServerLimits.maxAttachmentCeiling ~/ LimitInput.bytesPerMb;
      return (
        limits: null,
        error: 'Storage will not accept a file over $ceiling MB.',
      );
    }

    final counts = <String, TextEditingController>{
      'retention period': retentionDays,
      'history cap': historyCap,
    };
    final read = <String, int>{};
    for (final entry in counts.entries) {
      final value = LimitInput.parse(entry.value.text);
      if (value == LimitInput.invalid) {
        return (
          limits: null,
          error: 'The ${entry.key} must be a whole number.',
        );
      }
      read[entry.key] = value ?? ServerLimits.unlimited;
    }

    return (
      limits: ServerLimits(
        maxAttachmentBytes: bytes,
        messageRetentionDays: read['retention period']!,
        messageHistoryCap: read['history cap']!,
        dmRetentionDays: _dmRetentionDays,
        dmHistoryCap: _dmHistoryCap,
      ),
      error: null,
    );
  }
}
