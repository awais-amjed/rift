import '../../services/server_topic_watcher.dart';
import 'server_members_cubit.dart';

/// The members of the server this device's call is on, empty outside a call.
///
/// A second roster beside the app's own, which follows the selection. A call
/// outlives the selection — its member opens another server and the call
/// carries on in the middle of the window — and the call's tiles drew their
/// pictures and names from whichever server was selected. Opening another
/// server swapped every face in the call for a generated one, and the call's
/// bots stopped being known as bots, which is the key their sound is read
/// with. The call's surfaces read this one instead (`CallServerScope`).
///
/// It follows the call even while the call's server is the selected one, so
/// opening another server does not have to wait for a first load.
class CallMembersCubit extends ServerMembersCubit {
  CallMembersCubit({required super.session})
    : super(follow: WatchedServer.call);
}
