import 'dart:async';
import 'dart:io' as io;

import 'package:meta/meta.dart';
import 'package:restio/src/core/auth/authenticator.dart';
import 'package:restio/src/core/cache/cache.dart';
import 'package:restio/src/core/call.dart';
import 'package:restio/src/core/cancellable.dart';
import 'package:restio/src/core/client_certificate_jar.dart';
import 'package:restio/src/core/cookie_jar.dart';
import 'package:restio/src/core/dns/dns.dart';
import 'package:restio/src/core/exceptions.dart';
import 'package:restio/src/core/http/client_adapter.dart';
import 'package:restio/src/core/interceptor_chain.dart';
import 'package:restio/src/core/interceptors/interceptor.dart';
import 'package:restio/src/core/internal/bridge_interceptor.dart';
import 'package:restio/src/core/internal/connect_interceptor.dart';
import 'package:restio/src/core/internal/cookie_interceptor.dart';
import 'package:restio/src/core/internal/follow_up_interceptor.dart';
import 'package:restio/src/core/listeners.dart';
import 'package:restio/src/core/proxy.dart';
import 'package:restio/src/core/push/sse/connection.dart';
import 'package:restio/src/core/push/sse/event.dart';
import 'package:restio/src/core/push/sse/sse.dart';
import 'package:restio/src/core/push/sse/transformer.dart';
import 'package:restio/src/core/push/ws/connection.dart';
import 'package:restio/src/core/push/ws/ws.dart';
import 'package:restio/src/core/request/request.dart';
import 'package:restio/src/core/response/response.dart';

class Restio {
  final Duration connectTimeout;
  final Duration writeTimeout;
  final Duration receiveTimeout;
  final List<Interceptor> interceptors;
  final List<Interceptor> networkInterceptors;
  final CookieJar cookieJar;
  final ClientAdapter adapter;
  final Authenticator auth;
  final bool followRedirects;
  final int maxRedirects;
  final bool verifySSLCertificate;
  final String userAgent;
  final Proxy proxy;
  final bool withTrustedRoots;
  final ProgressCallback<Request> onUploadProgress;
  final ProgressCallback<Response> onDownloadProgress;
  final BadCertificateCallback onBadCertificate;
  final bool http2;
  final ClientCertificateJar clientCertificateJar;
  final Dns dns;
  final Cache cache;

  Restio({
    this.connectTimeout,
    this.writeTimeout,
    this.receiveTimeout,
    this.interceptors = const [],
    this.networkInterceptors = const [],
    this.cookieJar,
    ClientAdapter adapter,
    this.auth,
    this.followRedirects = true,
    this.maxRedirects = 5,
    this.verifySSLCertificate = false,
    this.userAgent,
    this.proxy,
    this.withTrustedRoots = true,
    this.onUploadProgress,
    this.onDownloadProgress,
    this.onBadCertificate,
    this.http2 = false,
    this.clientCertificateJar,
    this.dns,
    this.cache,
  })  : assert(interceptors != null),
        assert(maxRedirects != null),
        assert(followRedirects != null),
        adapter = adapter ?? DefaultClientAdapter();

  static const version = '0.6.0';

  Call newCall(Request request) {
    return _Call(client: this, request: request);
  }

  WebSocket newWebSocket(
    Request request, {
    List<String> protocols,
    Duration pingInterval,
  }) {
    return _WebSocket(
      request,
      protocols: protocols,
      pingInterval: pingInterval,
    );
  }

  Sse newSse(Request request) {
    return _Sse(this, request);
  }

  Restio copyWith({
    Duration connectTimeout,
    Duration writeTimeout,
    Duration receiveTimeout,
    List<Interceptor> interceptors,
    List<Interceptor> networkInterceptors,
    CookieJar cookieJar,
    ClientAdapter adapter,
    Authenticator auth,
    bool followRedirects,
    int maxRedirects,
    bool verifySSLCertificate,
    String userAgent,
    Proxy proxy,
    io.SecurityContext securityContext,
    bool withTrustedRoots,
    ProgressCallback<Request> onUploadProgress,
    ProgressCallback<Response> onDownloadProgress,
    BadCertificateCallback onBadCertificate,
    bool http2,
    ClientCertificateJar clientCertificateJar,
    Dns dns,
    Cache cache,
  }) {
    return Restio(
      connectTimeout: connectTimeout ?? this.connectTimeout,
      writeTimeout: writeTimeout ?? this.writeTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      interceptors: interceptors ?? this.interceptors,
      networkInterceptors: networkInterceptors ?? this.networkInterceptors,
      cookieJar: cookieJar ?? this.cookieJar,
      adapter: adapter ?? this.adapter,
      auth: auth ?? this.auth,
      followRedirects: followRedirects ?? this.followRedirects,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      verifySSLCertificate: verifySSLCertificate ?? this.verifySSLCertificate,
      userAgent: userAgent ?? this.userAgent,
      proxy: proxy ?? this.proxy,
      withTrustedRoots: withTrustedRoots ?? this.withTrustedRoots,
      onUploadProgress: onUploadProgress ?? this.onUploadProgress,
      onDownloadProgress: onDownloadProgress ?? this.onDownloadProgress,
      onBadCertificate: onBadCertificate ?? this.onBadCertificate,
      http2: http2 ?? this.http2,
      clientCertificateJar: clientCertificateJar ?? this.clientCertificateJar,
      dns: dns ?? this.dns,
      cache: cache ?? this.cache,
    );
  }
}

class _Call implements Call {
  final Restio client;
  @override
  final Request request;
  final _cancellable = Cancellable();
  var _executed = false;
  var _executing = false;

  _Call({
    this.client,
    this.request,
  });

  @override
  void cancel(String message) {
    _cancellable.cancel(message);
  }

  @override
  Future<Response> execute() async {
    if (!_executing && !isCancelled) {
      _executing = true;

      final adapter = client.adapter;

      try {
        return await adapter.execute(client, this, _cancellable);
      } finally {
        _executed = true;
      }
    } else {
      throw const RestioException('Call has already been executed');
    }
  }

  @override
  bool get isExecuted => _executed;

  @override
  bool get isCancelled => _cancellable.isCancelled;
}

class _WebSocket implements WebSocket {
  @override
  final Request request;
  final List<String> protocols;
  final Duration pingInterval;

  _WebSocket(
    this.request, {
    this.protocols,
    this.pingInterval,
  });

  @override
  Future<WebSocketConnection> open() async {
    // ignore: close_sinks
    final ws = await io.WebSocket.connect(
      request.uri.toUriString(),
      protocols: protocols,
      headers: request.headers?.toMap(),
    );

    ws.pingInterval = pingInterval;

    return _WebSocketConnection(ws);
  }
}

class _WebSocketConnection implements WebSocketConnection {
  final io.WebSocket _ws;
  Stream _stream;

  _WebSocketConnection(io.WebSocket ws) : _ws = ws;

  @override
  void addString(String text) => _ws.add(text);

  @override
  void addBytes(List<int> bytes) => _ws.add(bytes);

  @override
  Future addStream(Stream stream) => _ws.addStream(stream);

  @override
  void addUtf8Text(List<int> bytes) => _ws.addUtf8Text(bytes);

  @override
  Future close([
    int code,
    String reason,
  ]) {
    return _ws.close(code, reason);
  }

  @override
  int get closeCode => _ws.closeCode;

  @override
  String get closeReason => _ws.closeReason;

  @override
  String get extensions => _ws.extensions;

  @override
  String get protocol => _ws.protocol;

  @override
  int get readyState => _ws.readyState;

  @override
  Future get done => _ws.done;

  @override
  Stream<dynamic> get stream => _stream ??= _ws.asBroadcastStream();
}

class _Sse implements Sse {
  final Restio _client;
  @override
  final Request request;

  final SseTransformer _transformer;

  _Sse(
    this._client,
    this.request, [
    Retry retry,
  ]) : _transformer = SseTransformer(retry: retry);

  @override
  Future<SseConnection> open() async {
    // ignore: close_sinks
    StreamController<Event> incomingController;

    incomingController = StreamController<Event>.broadcast(
      onListen: () async {
        final realRequest = request.copyWith(
          method: 'GET',
          headers: (request.headers.toBuilder()
                ..set('accept', 'text/event-stream'))
              .build(),
        );

        final call = _client.newCall(realRequest);

        try {
          final response = await call.execute();

          if (response.code == 200) {
            response.body.data.transform(_transformer).listen((event) {
              if (incomingController.hasListener &&
                  !incomingController.isClosed &&
                  !incomingController.isPaused) {
                incomingController.add(event);
              }
            }, onError: (e, stackTrace) {
              if (incomingController.hasListener &&
                  !incomingController.isClosed &&
                  !incomingController.isPaused) {
                incomingController.addError(e, stackTrace);
              }
            });

            return;
          }
        } catch (e, stackTrace) {
          print(e);
          print(stackTrace);
        }

        incomingController
            .addError(RestioException('Failed to connect to ${request.uri}'));
      },
    );

    return _SseConnection(incomingController);
  }
}

class _SseConnection implements SseConnection {
  final StreamController<Event> controller;

  _SseConnection(this.controller);

  @override
  Stream<Event> get stream => controller.stream;

  @override
  Future<void> close() async {
    await controller.close();
  }

  @override
  bool get isClosed => controller.isClosed;
}

class DefaultClientAdapter extends ClientAdapter {
  @override
  @mustCallSuper
  Future<Response> execute(
    Restio client,
    Call call, [
    Cancellable cancellable,
  ]) async {
    final interceptors = [
      // Interceptors.
      if (client.interceptors != null)
        ...client.interceptors,
      // Redirects.
      FollowUpInterceptor(client),
      // Cookies.
      CookieInterceptor(client.cookieJar),
      BridgeInterceptor(client),
      // Cache.
      CacheInterceptor(client),
      // Network Interceptors.
      if (client.networkInterceptors != null)
        ...client.networkInterceptors,
      // Connection.
      ConnectInterceptor(
        client: client,
        cancellable: cancellable,
      ),
    ];

    final chain = InterceptorChain(
      call: call,
      request: call.request,
      interceptors: interceptors,
      index: 0,
    );

    return chain.proceed(call.request);
  }
}
