import 'package:equatable/equatable.dart';

/// A window about to be shared, as far as the desktop said who it belongs
/// to: on GNOME under Wayland the app and title it saved for the pick, on
/// X11 the window's own app (`WM_CLASS`), process and title. What finds the
/// sound that goes with it (`ShareSoundMatch`).
class SharedWindow extends Equatable {
  /// The app: a desktop file id (`google-chrome.desktop`,
  /// `org.mozilla.firefox`) or an X11 class (`google-chrome`). Empty when
  /// the desktop did not say.
  final String appId;
  final String title;

  /// X11 only: the process that drew it.
  final int? pid;

  const SharedWindow({required this.appId, required this.title, this.pid});

  @override
  List<Object?> get props => [appId, title, pid];
}
