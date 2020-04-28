import 'package:restio/src/core/push/ws/connection.dart';
import 'package:restio/src/core/request/request.dart';

export 'connection.dart';

abstract class WebSocket {
  Request get request;

  Future<WebSocketConnection> open();
}
