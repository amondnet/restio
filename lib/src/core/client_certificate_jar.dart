import 'package:restio/src/core/client_certificate.dart';

abstract class ClientCertificateJar {
  Future<ClientCertificate> get(
    String host,
    int port,
  );
}
