import 'package:listener_engine/listener_engine.dart';

class ServerEndpoint {
  const ServerEndpoint({
    required this.fullName,
    required this.host,
    required this.port,
  });

  factory ServerEndpoint.fromDiscovery(DiscoveredServiceEvent service) {
    return ServerEndpoint(
      fullName: service.fullName,
      host: service.host,
      port: service.port,
    );
  }

  factory ServerEndpoint.manual({required String host, required int port}) {
    final normalizedHost = host.trim();
    return ServerEndpoint(
      fullName: normalizedHost,
      host: normalizedHost,
      port: port,
    );
  }

  final String fullName;
  final String host;
  final int port;

  String get displayName {
    const serviceMarker = '._lstn.';
    final markerIndex = fullName.indexOf(serviceMarker);
    return markerIndex == -1 ? fullName : fullName.substring(0, markerIndex);
  }

  String get displayHost {
    return host.endsWith('.') ? host.substring(0, host.length - 1) : host;
  }

  String get address => '$displayHost:$port';
}
