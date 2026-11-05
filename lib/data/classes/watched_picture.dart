import 'package:equatable/equatable.dart';

/// A share watched through the Rust watch connection: the runner's texture
/// its pictures are drawn into, and their size once the first has arrived.
///
/// Zero by zero until then, which a tile shows as a picture on its way rather
/// than as a stream with nothing in it.
class WatchedPicture extends Equatable {
  final int textureId;
  final int width;
  final int height;

  const WatchedPicture({
    required this.textureId,
    this.width = 0,
    this.height = 0,
  });

  bool get hasPicture => width > 0 && height > 0;

  WatchedPicture sized(int width, int height) =>
      WatchedPicture(textureId: textureId, width: width, height: height);

  @override
  List<Object?> get props => [textureId, width, height];
}
