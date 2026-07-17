import 'package:grpc/grpc.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart';

class ListenerGrpc {
  ListenerGrpc._(this.channel)
    : controlClient = ListenerControlClient(channel),
      libraryClient = ListenerLibraryClient(channel);

  factory ListenerGrpc.connect() {
    final channel = ClientChannel(
      "127.0.0.1",
      port: 5779,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );

    return ListenerGrpc._(channel);
  }

  final ClientChannel channel;
  final ListenerControlClient controlClient;
  final ListenerLibraryClient libraryClient;

  Future<void> close() => channel.shutdown();
}
