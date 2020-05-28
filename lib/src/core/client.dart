import 'dart:async';
import 'dart:io' as io;

import 'package:restio/src/common/closeable.dart';
import 'package:restio/src/common/helpers.dart';
import 'package:restio/src/core/cache/cache.dart';
import 'package:restio/src/core/call/call.dart';
import 'package:restio/src/core/call/cancellable.dart';
import 'package:restio/src/core/certificate/certificate.dart';
import 'package:restio/src/core/connection/http_connection_pool.dart';
import 'package:restio/src/core/cookie/cookie_jar.dart';
import 'package:restio/src/core/exceptions.dart';
import 'package:restio/src/core/interceptors/interceptor.dart';
import 'package:restio/src/core/internal/bridge_interceptor.dart';
import 'package:restio/src/core/internal/connect_interceptor.dart';
import 'package:restio/src/core/internal/cookie_interceptor.dart';
import 'package:restio/src/core/internal/follow_up_interceptor.dart';
import 'package:restio/src/core/internal/interceptor_chain.dart';
import 'package:restio/src/core/listeners.dart';
import 'package:restio/src/core/push/sse/sse.dart';
import 'package:restio/src/core/push/ws/ws.dart';
import 'package:restio/src/core/redirect/redirect_policy.dart';
import 'package:restio/src/core/request/request.dart';
import 'package:restio/src/core/request/request_options.dart';
import 'package:restio/src/core/response/response.dart';

part 'call.dart';
part 'sse.dart';
part 'ws.dart';

class Restio implements Closeable {
  final List<Interceptor> interceptors;
  final List<Interceptor> networkInterceptors;
  final CookieJar cookieJar;
  final bool withTrustedRoots;
  final ProgressCallback<Request> onUploadProgress;
  final ProgressCallback<Response> onDownloadProgress;
  final BadCertificateCallback onBadCertificate;
  final bool http2;
  final List<Certificate> certificates;
  final Cache cache;
  final List<RedirectPolicy> redirectPolicies;
  final RequestOptions options;
  final Duration idleTimeout;
  HttpConnectionPool _httpConnectionPool;

  Restio({
    this.interceptors,
    this.networkInterceptors,
    this.cookieJar,
    this.withTrustedRoots = true,
    this.onUploadProgress,
    this.onDownloadProgress,
    this.onBadCertificate,
    this.http2 = false,
    this.certificates,
    this.cache,
    this.redirectPolicies,
    RequestOptions options,
    this.idleTimeout,
  }) : options = options ?? RequestOptions.empty {
    _httpConnectionPool = HttpConnectionPool(this, idleTimeout: idleTimeout);
  }

  static const version = '0.7.1';

  HttpConnectionPool get httpConnectionPool => _httpConnectionPool;

  Call newCall(Request request) {
    return _Call(client: this, request: request);
  }

  WebSocket newWebSocket(
    Request request, {
    List<String> protocols,
    Duration pingInterval,
  }) {
    return _WebSocket(
      request.copyWith(options: mergeOptions(this, request)),
      protocols: protocols,
      pingInterval: pingInterval,
    );
  }

  Sse newSse(
    Request request, {
    String lastEventId,
    Duration retryInterval,
    int maxRetries,
  }) {
    return _Sse(
      this,
      request,
      lastEventId: lastEventId,
      retryInterval: retryInterval,
      maxRetries: maxRetries,
    );
  }

  Restio copyWith({
    List<Interceptor> interceptors,
    List<Interceptor> networkInterceptors,
    CookieJar cookieJar,
    bool withTrustedRoots,
    ProgressCallback<Request> onUploadProgress,
    ProgressCallback<Response> onDownloadProgress,
    BadCertificateCallback onBadCertificate,
    bool http2,
    List<Certificate> certificates,
    Cache cache,
    List<RedirectPolicy> redirectPolicies,
    RequestOptions options,
    Duration idleTimeout,
  }) {
    return Restio(
      interceptors: interceptors ?? this.interceptors,
      networkInterceptors: networkInterceptors ?? this.networkInterceptors,
      cookieJar: cookieJar ?? this.cookieJar,
      withTrustedRoots: withTrustedRoots ?? this.withTrustedRoots,
      onUploadProgress: onUploadProgress ?? this.onUploadProgress,
      onDownloadProgress: onDownloadProgress ?? this.onDownloadProgress,
      onBadCertificate: onBadCertificate ?? this.onBadCertificate,
      http2: http2 ?? this.http2,
      certificates: certificates ?? this.certificates,
      cache: cache ?? this.cache,
      redirectPolicies: redirectPolicies ?? this.redirectPolicies,
      options: options ?? this.options,
      idleTimeout: idleTimeout ?? this.idleTimeout,
    );
  }

  @override
  Future<void> close() async {
    await _httpConnectionPool.close();
  }

  @override
  bool get isClosed => _httpConnectionPool.isClosed;
}
