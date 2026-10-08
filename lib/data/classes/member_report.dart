import 'package:equatable/equatable.dart';

import '../enums/member_report_reason.dart';
import '../enums/report_outcome.dart';

/// One row of a server's `reports`, as a reviewer reads it.
///
/// A message report carries the message's **sealed envelope** as it was when
/// reported — copied by the server, never sent by the reporter — so a
/// reviewer's client opens it with the channel key it already holds and
/// checks the author's signature. The words are never in this row; see
/// [ReportedMessage].
class MemberReport extends Equatable {
  final int id;
  final DateTime createdAt;

  /// Null once the reporter has left the server. The report stays true.
  final String? reporterId;

  /// Null for a message no member sent — a webhook's.
  final String? targetId;
  final MemberReportReason reason;
  final String? note;

  /// Null for a report about a member rather than a message.
  final ReportedMessage? message;

  /// Who filed it and who it is about, as the reviewer's server shows them.
  /// Null when the row is gone — the reporter left, or it was a webhook.
  final ReportPerson? reporter;
  final ReportPerson? target;

  /// The reported message's channel, or null when the reviewer cannot see it
  /// (a private channel they are not inside) or it was not a message.
  final String? channelName;

  /// Null while open.
  final ReportOutcome? outcome;
  final String? resolvedBy;
  final DateTime? resolvedAt;

  const MemberReport({
    required this.id,
    required this.createdAt,
    required this.reason,
    this.reporterId,
    this.targetId,
    this.note,
    this.message,
    this.reporter,
    this.target,
    this.channelName,
    this.outcome,
    this.resolvedBy,
    this.resolvedAt,
  });

  bool get isOpen => outcome == null;

  factory MemberReport.fromJson(Map<String, dynamic> json) {
    final messageId = (json['message_id'] as num?)?.toInt();
    return MemberReport(
      id: (json['id'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      reporterId: json['reporter_id'] as String?,
      targetId: json['target_id'] as String?,
      reason: MemberReportReason.fromString(json['reason'] as String?),
      note: json['note'] as String?,
      message: messageId == null
          ? null
          : ReportedMessage(
              id: messageId,
              channelId: json['channel_id'] as String,
              createdAt: DateTime.parse(json['message_created_at'] as String),
              originName: json['origin_name'] as String?,
              ciphertext: json['ciphertext'] as String,
              nonce: json['nonce'] as String?,
              signature: json['signature'] as String?,
              keyVersion: (json['key_version'] as num).toInt(),
            ),
      reporter: ReportPerson.fromJson(json['reporter']),
      target: ReportPerson.fromJson(json['target']),
      channelName: (json['channel'] as Map?)?['name'] as String?,
      outcome: ReportOutcome.fromString(json['outcome'] as String?),
      resolvedBy: json['resolved_by'] as String?,
      resolvedAt: DateTime.tryParse(json['resolved_at'] as String? ?? ''),
    );
  }

  @override
  List<Object?> get props => [
    id,
    createdAt,
    reporterId,
    targetId,
    reason,
    note,
    message,
    reporter,
    target,
    channelName,
    outcome,
    resolvedBy,
    resolvedAt,
  ];
}

/// The envelope a message report kept: exactly the columns `messages` had,
/// so it opens with the code that opens any message.
class ReportedMessage extends Equatable {
  final int id;
  final String channelId;
  final DateTime createdAt;

  /// A webhook's name, for a message no member sent.
  final String? originName;
  final String ciphertext;
  final String? nonce;
  final String? signature;

  /// 0 for a message sent in the clear (a webhook's, a bot's), whose
  /// [ciphertext] is its text.
  final int keyVersion;

  const ReportedMessage({
    required this.id,
    required this.channelId,
    required this.createdAt,
    required this.ciphertext,
    required this.keyVersion,
    this.originName,
    this.nonce,
    this.signature,
  });

  @override
  List<Object?> get props => [
    id,
    channelId,
    createdAt,
    originName,
    ciphertext,
    nonce,
    signature,
    keyVersion,
  ];
}

/// A person named on a report, as their row stood when the list was read.
class ReportPerson extends Equatable {
  final String displayName;
  final String username;
  final String? avatarPath;

  /// Their Ed25519 key (base64), which is what checks a reported message's
  /// signature. Null on the reporter, who is never checked.
  final String? publicKey;
  final bool isBanned;

  /// Out until an invite brings them back — a kick, which is a ban to the
  /// server, so [isBanned] is true as well.
  final bool isKicked;
  final DateTime? timedOutUntil;

  const ReportPerson({
    required this.displayName,
    required this.username,
    this.avatarPath,
    this.publicKey,
    this.isBanned = false,
    this.isKicked = false,
    this.timedOutUntil,
  });

  bool get isTimedOut =>
      timedOutUntil != null && timedOutUntil!.isAfter(DateTime.now());

  static ReportPerson? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return ReportPerson(
      displayName: json['display_name'] as String? ?? 'Unknown',
      username: json['username'] as String? ?? '',
      avatarPath: json['avatar_path'] as String?,
      publicKey: json['public_key'] as String?,
      isBanned: json['is_banned'] == true,
      isKicked: json['kicked_at'] != null,
      timedOutUntil: DateTime.tryParse(
        json['timed_out_until'] as String? ?? '',
      )?.toLocal(),
    );
  }

  @override
  List<Object?> get props => [
    displayName,
    username,
    avatarPath,
    publicKey,
    isBanned,
    isKicked,
    timedOutUntil,
  ];
}
