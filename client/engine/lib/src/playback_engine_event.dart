import 'package:equatable/equatable.dart';

sealed class PlaybackEngineEvent extends Equatable {
  const PlaybackEngineEvent();
}

final class Ended extends PlaybackEngineEvent {
  const Ended();

  @override
  List<Object?> get props => [];
}

final class Failed extends PlaybackEngineEvent {
  const Failed();

  @override
  List<Object?> get props => [];
}

final class DiscoveredServiceEvent extends PlaybackEngineEvent {
  const DiscoveredServiceEvent({
    required this.fullName,
    required this.host,
    required this.port,
  });

  final String fullName;
  final String host;
  final int port;

  @override
  List<Object?> get props => [fullName, host, port];
}
