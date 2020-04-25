import 'package:restio/src/core/push/sse/event.dart';

abstract class SseConnection {
  Stream<Event> get stream;

  Future close();

  bool get isClosed;
}
