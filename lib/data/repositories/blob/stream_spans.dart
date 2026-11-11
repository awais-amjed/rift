import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

/// A file read from a stream by span, forward only: each span starts at or
/// after the one before it started. What lies between is read past and let
/// go, so a box at the end of a big file costs a pass over it, not a copy.
class StreamSpans {
  final StreamIterator<Uint8List> _pieces;

  /// Where [_buffer] starts in the file.
  int _at = 0;
  Uint8List _buffer = Uint8List(0);
  bool _ended = false;

  StreamSpans(Stream<Uint8List> pieces) : _pieces = StreamIterator(pieces);

  /// Up to [length] bytes from [offset]; fewer only where the file ends.
  Future<Uint8List> read(int offset, int length) async {
    if (offset < _at) {
      throw StateError('Read at $offset after one at $_at: forward only');
    }
    // Let go of what lies before it.
    while (offset >= _at + _buffer.length && !_ended) {
      _at += _buffer.length;
      _buffer = Uint8List(0);
      await _more();
    }
    final skip = math.min(offset - _at, _buffer.length);
    _buffer = Uint8List.sublistView(_buffer, skip);
    _at += skip;
    final all = BytesBuilder(copy: false)..add(_buffer);
    while (all.length < length && !_ended) {
      if (!await _pieces.moveNext()) {
        _ended = true;
        break;
      }
      all.add(_pieces.current);
    }
    _buffer = all.takeBytes();
    return Uint8List.sublistView(_buffer, 0, math.min(length, _buffer.length));
  }

  Future<void> _more() async {
    if (await _pieces.moveNext()) {
      _buffer = _pieces.current;
    } else {
      _ended = true;
    }
  }

  Future<void> close() => _pieces.cancel();
}
