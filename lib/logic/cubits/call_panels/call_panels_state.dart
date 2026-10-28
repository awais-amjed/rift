part of 'call_panels_cubit.dart';

class CallPanelsState extends Equatable {
  /// The live players of the bots in this device's call, newest first.
  final List<ChatMessage> panels;

  /// The channel each of [panels] was posted in, by message id: a press is
  /// signed for that channel, whichever one it was pressed from.
  final Map<String, String> channelOf;

  const CallPanelsState({this.panels = const [], this.channelOf = const {}});

  @override
  List<Object?> get props => [panels, channelOf];
}
