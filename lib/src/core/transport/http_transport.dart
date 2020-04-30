import 'dart:async';
import 'dart:io';

import 'package:ip/ip.dart';
import 'package:restio/src/common/helpers.dart';
import 'package:restio/src/core/client.dart';
import 'package:restio/src/core/exceptions.dart';
import 'package:restio/src/core/request/header/headers.dart';
import 'package:restio/src/core/request/header/headers_builder.dart';
import 'package:restio/src/core/request/header/media_type.dart';
import 'package:restio/src/core/request/request.dart';
import 'package:restio/src/core/response/response.dart';
import 'package:restio/src/core/transport/transport.dart';

class HttpTransport implements Transport {
  @override
  final Restio client;
  HttpClient _httpClient;
  var _isClosed = false;

  HttpTransport(this.client) : assert(client != null);

  Future<HttpClient> onCreate(
    Restio client,
    HttpClient httpClient,
  ) async {
    return httpClient;
  }

  Future<HttpClient> _buildHttpClient(
    Restio client,
    Request request,
  ) async {
    final securityContext =
        SecurityContext(withTrustedRoots: client.withTrustedRoots ?? true);

    final clientCertificate = await client.clientCertificateJar?.get(
      request.uri.host,
      request.uri.effectivePort,
    );

    if (clientCertificate != null) {
      final certificate = clientCertificate.certificate;
      final privateKey = clientCertificate.privateKey;
      final password = clientCertificate.password;

      if (certificate != null) {
        securityContext.useCertificateChainBytes(
          certificate,
          password: password,
        );
      }

      if (privateKey != null) {
        securityContext.usePrivateKeyBytes(
          privateKey,
          password: password,
        );
      }
    }

    var httpClient = HttpClient(context: securityContext);

    httpClient = await onCreate(client, httpClient) ?? httpClient;

    httpClient.badCertificateCallback = (cert, host, port) {
      // TODO: CertificatePinners: https://github.com/dart-lang/sdk/issues/35981.
      return !client.verifySSLCertificate ||
          (client.onBadCertificate?.call(cert, host, port) ?? false);
    };

    return httpClient;
  }

  @override
  Future<void> cancel() async {
    if (isClosed) {
      return;
    }

    _isClosed = true;

    _httpClient?.close(force: true);
  }

  @override
  Future<void> close() async {
    if (isClosed) {
      return;
    }

    _isClosed = true;

    _httpClient?.close();
  }

  @override
  bool get isClosed => _isClosed;

  @override
  Future<Response> send(final Request request) async {
    HttpClientRequest clientRequest;
    var uri = request.uri;

    _httpClient = await _buildHttpClient(client, request);

    final proxy = client.proxy;
    var hasProxy = false;

    // Proxy.
    if (proxy != null &&
        (proxy.http && uri.scheme == 'http' ||
            proxy.https && uri.scheme == 'https')) {
      hasProxy = true;
      _httpClient.findProxy = (uri) {
        return 'PROXY ${proxy.host}:${proxy.port};';
      };
    }

    // Host.
    IpAddress dnsIp;
    
    // Verificar se não é um IP.
    // Busca o real endereço (IP) do host através de um DNS.
    if (client.dns != null && !isIp(uri.host)) {
      final addresses = await client.dns.lookup(uri.host);

      if (addresses != null && addresses.isNotEmpty) {
        dnsIp = addresses[0];
        uri = uri.copyWith(host: dnsIp.toString());
      }
    }

    try {
      if (client.connectTimeout != null && !client.connectTimeout.isNegative) {
        clientRequest = await _httpClient
            .openUrl(request.method, uri.toUri())
            .timeout(client.connectTimeout);
      } else {
        clientRequest = await _httpClient.openUrl(
          request.method,
          uri.toUri(),
        );
      }

      if (hasProxy) {
        clientRequest.headers.add('proxy-connection', 'Keep-Alive');
      }

      // Não seguir redirecionamentos.
      clientRequest.followRedirects = false;

      // Não descomprimir a resposta.
      _httpClient.autoUncompress = false;

      // User-Agent.
      if (!request.headers.has(HttpHeaders.userAgentHeader)) {
        if (client.userAgent != null) {
          clientRequest.headers
              .set(HttpHeaders.userAgentHeader, client.userAgent);
        } else {
          clientRequest.headers
              .set(HttpHeaders.userAgentHeader, 'Restio/${Restio.version}');
        }
      }

      // Content-Type.
      if (!request.headers.has(HttpHeaders.contentTypeHeader) &&
          request.body?.contentType != null) {
        clientRequest.headers.contentType =
            request.body.contentType.toContentType();
      }

      // Accept-Encoding.
      if (!request.headers.has(HttpHeaders.acceptEncodingHeader)) {
        clientRequest.headers
            .set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate, br');
      }

      // Connection.
      if (!request.headers.has(HttpHeaders.connectionHeader)) {
        clientRequest.headers.set(HttpHeaders.connectionHeader, 'Keep-Alive');
      }

      // Headers.
      request.headers?.forEach((item) {
        switch (item.name) {
          case HttpHeaders.userAgentHeader:
            clientRequest.headers.set(item.name, item.value);
            break;
          default:
            clientRequest.headers.add(item.name, item.value);
        }
      });

      // Host.
      if (!request.headers.has(HttpHeaders.hostHeader) && dnsIp != null) {
        clientRequest.headers.set('Host', uri.host);
      }

      // Body.
      if (request.body != null) {
        final future = _writeBody(clientRequest, request, client);
        // Escreve os dados.
        if (client.writeTimeout != null && !client.writeTimeout.isNegative) {
          await future.timeout(client.writeTimeout);
        } else {
          await future;
        }
      }

      // Resposta.
      HttpClientResponse response;

      if (client.receiveTimeout != null && !client.receiveTimeout.isNegative) {
        response = await clientRequest.close().timeout(client.receiveTimeout);
      } else {
        response = await clientRequest.close();
      }

      // Monta a resposta.
      final res = Response(
        body: null,
        code: response.statusCode,
        headers: _obtainHeadersfromHttpHeaders(response.headers),
        message: response.reasonPhrase,
        connectionInfo: response.connectionInfo,
        certificate: response.certificate,
        dnsIp: dnsIp,
      );

      return res.copyWith(
        body: ResponseBody.stream(
          response.cast<List<int>>(),
          contentType: MediaType.fromContentType(response.headers.contentType),
          contentLength: response.headers.contentLength,
        ),
      );
    } on TimeoutException {
      throw const TimedOutException(''); // connect time out
    }
  }

  static Headers _obtainHeadersfromHttpHeaders(
    HttpHeaders httpHeaders,
  ) {
    final headers = HeadersBuilder();
    httpHeaders.forEach(headers.add);
    return headers.build();
  }

  static Future<void> _writeBody(
    HttpClientRequest clientRequest,
    Request request,
    Restio client,
  ) async {
    var total = 0;

    final listener = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        sink.add(chunk);
        total += chunk.length;
        client.onUploadProgress?.call(request, chunk.length, total, false);
      },
      handleDone: (sink) {
        client.onUploadProgress?.call(request, 0, total, true);
        sink.close();
      },
    );

    final stream = request.body.write().transform(listener);

    if (request.body.contentLength == null || request.body.contentLength <= 0) {
      final data = await readStream(stream);
      clientRequest.contentLength = data.length;
      clientRequest.add(data);
    } else {
      clientRequest.contentLength = request.body.contentLength;
      await clientRequest.addStream(stream);
    }
  }
}
