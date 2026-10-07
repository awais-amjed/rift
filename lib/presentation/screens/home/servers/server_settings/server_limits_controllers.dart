import 'package:flutter/widgets.dart';

import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/services/limit_input.dart';

/// The limit fields of the server settings dialog, as one object.
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

  /// What a call may cost. Bandwidth rather than disk, which
  /// is why the dialog shows them under their own heading — but they are read
  /// and validated with the rest, because [ServerLimits] travels whole.
  final voiceParticipants = TextEditingController();
  final shareMbps = TextEditingController();

  /// How large the place may get. [storageMb] is megabytes in
  /// the box and bytes on the wire, like [attachmentMb] — nobody sets a disk
  /// budget in bytes either.
  final maxMembers = TextEditingController();
  final storageMb = TextEditingController();

  /// How many people one member may start a DM with in an hour. The one box
  /// here that is on by default, which is why it sits under its own heading.
  final dmOpenings = TextEditingController();

  /// The DM settings as last seeded. This dialog doesn't show them — they are
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
    voiceParticipants.text = LimitInput.textOf(limits.maxVoiceParticipants);
    shareMbps.text = LimitInput.textOf(limits.maxShareMbps);
    maxMembers.text = LimitInput.textOf(limits.maxMembers);
    storageMb.text = limits.maxStorageBytes == ServerLimits.unlimited
        ? ''
        : LimitInput.megabytesOf(limits.maxStorageBytes);
    dmOpenings.text = LimitInput.textOf(limits.dmOpeningsPerHour);
    _dmRetentionDays = limits.dmRetentionDays;
    _dmHistoryCap = limits.dmHistoryCap;
  }

  void dispose() {
    attachmentMb.dispose();
    retentionDays.dispose();
    historyCap.dispose();
    voiceParticipants.dispose();
    shareMbps.dispose();
    maxMembers.dispose();
    storageMb.dispose();
    dmOpenings.dispose();
  }

  /// The limits as typed, or the sentence explaining why they aren't valid.
  ///
  /// A blank count means [ServerLimits.unlimited] — that is what an empty box
  /// says to a reader, and it matches how the fields are seeded. The size cap
  /// is the exception: it cannot be blank and it cannot be zero, because a
  /// size has no "off" and a cap of nothing would forbid every attachment.
  /// Nor can it pass [maxFileBytes], the largest file the machine accepts.
  ({ServerLimits? limits, String? error}) read({required int maxFileBytes}) {
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
    if (bytes > maxFileBytes) {
      final ceiling = maxFileBytes ~/ LimitInput.bytesPerMb;
      return (
        limits: null,
        error:
            'This server takes files up to $ceiling MB. Its operator can '
            'raise that in the console.',
      );
    }

    // A size, so megabytes rather than a count — but unlike the attachment
    // cap it may be blank, which is what "no limit" looks like in every other
    // box here.
    final int storageBytes;
    if (storageMb.text.trim().isEmpty) {
      storageBytes = ServerLimits.unlimited;
    } else {
      final parsed = LimitInput.parseMegabytes(storageMb.text);
      if (parsed == null || parsed == LimitInput.invalid) {
        return (
          limits: null,
          error: 'The storage limit must be a whole number of megabytes.',
        );
      }
      storageBytes = parsed;
    }

    final counts = <String, TextEditingController>{
      'retention period': retentionDays,
      'history cap': historyCap,
      'call size': voiceParticipants,
      'screen share limit': shareMbps,
      'member limit': maxMembers,
      'new conversation limit': dmOpenings,
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
        maxVoiceParticipants: read['call size']!,
        maxShareMbps: read['screen share limit']!,
        maxMembers: read['member limit']!,
        maxStorageBytes: storageBytes,
        dmOpeningsPerHour: read['new conversation limit']!,
      ),
      error: null,
    );
  }
}
