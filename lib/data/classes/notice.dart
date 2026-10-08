import 'package:equatable/equatable.dart';

/// How a [Notice] is drawn.
enum NoticeKind { info, success, error }

/// Something a cubit has to tell the person — a failure, or a change they
/// did not ask for — carried in its state and shown once by
/// `NoticeListeners`.
///
/// A cubit opens no UI itself (`CODE_STYLE.md` §8): it cannot tell which
/// screen is up or whether something is already saying it. It sets a notice;
/// the presentation layer decides how to show it.
///
/// Every notice has its own [id], so the same words twice are two notices.
/// States compare by value, and without the id a second identical failure
/// would make an equal state that `emit` drops — the retry that failed again
/// would say nothing.
class Notice extends Equatable {
  static int _issued = 0;

  final int id;
  final NoticeKind kind;
  final String title;
  final String message;

  /// How long it stays up.
  final Duration duration;

  static const Duration short = Duration(seconds: 3);

  /// For a sentence somebody has to read to act on — why a share stopped.
  static const Duration long = Duration(seconds: 6);

  // Not const: each one takes the next id.
  // ignore: prefer_const_constructors_in_immutables
  Notice.error(this.message, {this.duration = short})
    : id = ++_issued,
      kind = NoticeKind.error,
      title = 'Error';

  // ignore: prefer_const_constructors_in_immutables
  Notice.info(this.title, this.message, {this.duration = short})
    : id = ++_issued,
      kind = NoticeKind.info;

  // ignore: prefer_const_constructors_in_immutables
  Notice.success(this.title, this.message, {this.duration = short})
    : id = ++_issued,
      kind = NoticeKind.success;

  @override
  List<Object?> get props => [id, kind, title, message, duration];
}
