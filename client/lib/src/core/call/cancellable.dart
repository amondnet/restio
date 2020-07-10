import 'dart:async';

import 'package:restio/restio.dart';
import 'package:restio/src/core/exceptions.dart';

typedef CancellableCallback = FutureOr<void> Function(String message);

class Cancellable implements Closeable {
  final Completer<CancelledException> _completer;
  StreamSubscription<CancelledException> _streamSubscription;
  CancelledException _exception;
  final _actions = <CancellableCallback>[];

  Cancellable() : _completer = Completer() {
    _streamSubscription = _completer.future.asStream().listen((e) {
      for (final action in _actions) {
        action(e.message);
      }
    });
  }

  void add(CancellableCallback action) {
    _actions.add(action);
  }

  void remove(CancellableCallback action) {
    _actions.remove(action);
  }

  void clear() {
    _actions.clear();
  }

  void cancel([String message]) {
    if (isCancelled) {
      throw const RestioException('The call has been cancelled');
    }

    if (isClosed) {
      throw StateError('The cancellable is closed');
    }

    _exception = CancelledException(message);
    _completer.complete(_exception);
  }

  bool get isCancelled => _completer.isCompleted;

  @override
  Future<void> close() async {
    if (isClosed) {
      return;
    }

    clear();

    await _streamSubscription.cancel();
    _streamSubscription = null;
  }

  @override
  bool get isClosed => _streamSubscription == null;

  CancelledException get exception => _exception;
}
