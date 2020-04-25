import 'dart:async';

import 'package:ip/ip.dart';
import 'package:meta/meta.dart';
import 'package:restio/src/core/cancellable.dart';
import 'package:restio/src/core/chain.dart';
import 'package:restio/src/core/client.dart';
import 'package:restio/src/core/http/http2_transport.dart';
import 'package:restio/src/core/http/http_transport.dart';
import 'package:restio/src/core/http/transport.dart';
import 'package:restio/src/core/interceptors/interceptor.dart';
import 'package:restio/src/core/request/request.dart';
import 'package:restio/src/core/response/response.dart';
import 'package:restio/src/helpers.dart';

class ConnectInterceptor implements Interceptor {
  final Restio client;
  final Cancellable cancellable;

  ConnectInterceptor({
    @required this.client,
    this.cancellable,
  }) : assert(client != null);

  @override
  Future<Response> intercept(Chain chain) async {
    return _execute(chain.request);
  }

  static Transport _createHttpTransport(Restio client) {
    return HttpTransport(client);
  }

  static Transport _createHttp2Transport(Restio client) {
    return Http2Transport(client);
  }

  Future<Response> _execute(final Request request) async {
    final sentAt = DateTime.now();

    final transport = client.isHttp2 == true
        ? _createHttp2Transport(client)
        : _createHttpTransport(client);

    if (cancellable != null && cancellable.isCancelled) {
      throw cancellable.exception;
    }

    // ignore: unawaited_futures
    cancellable?.whenCancel?.catchError((e, stackTrace) async {
      try {
        await transport.cancel();
      } catch (e) {
        // nada.
      }
    });

    Request connectRequest;

    try {
      IpAddress dnsIp;

      // Verificar se não é um IP.
      // Busca o real endereço (IP) do host através de um DNS.
      if (client.dns != null && !isIp(request.uri.host)) {
        final addresses = await client.dns.lookup(request.uri.host);

        if (addresses != null && addresses.isNotEmpty) {
          dnsIp = addresses[0];

          connectRequest = request.copyWith(
            uri: request.uri.copyWith(host: dnsIp.toString()),
          );
        }
      }

      final response = await transport.send(connectRequest ?? request);

      final receivedAt = DateTime.now();

      final spentMilliseconds =
          receivedAt.millisecondsSinceEpoch - sentAt.millisecondsSinceEpoch;

      return response.copyWith(
        request: request,
        dnsIp: dnsIp,
        sentAt: sentAt,
        receivedAt: receivedAt,
        spentMilliseconds: spentMilliseconds,
        totalMilliseconds: spentMilliseconds,
      );
    } on Exception {
      if (cancellable != null && cancellable.isCancelled) {
        throw cancellable.exception;
      } else {
        rethrow;
      }
    } finally {
      // Encerra a conexão, pois ela não é persistente.
      await transport.close();
    }
  }
}
