import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/app.dart';
import 'package:listener_front/src/repositories/artwork_repository.dart';
import 'package:listener_front/src/services/listener_grpc.dart';
import 'package:listener_front/src/services/playback_engine.dart';
import 'package:listener_front/src/services/playback_engine_event.dart';
import 'package:listener_front/src/view_models/library_cubit.dart';
import 'package:listener_front/src/view_models/playback_cubit.dart';
import 'package:listener_front/src/widgets/server_discovery_page.dart';

void main() {
  final engine = ListenerEngine.open();
  runApp(MainApp(home: _ListenerBootstrap(engine: engine)));
}

class _ListenerBootstrap extends StatefulWidget {
  const _ListenerBootstrap({required this.engine});

  final ListenerEngine engine;

  @override
  State<_ListenerBootstrap> createState() => _ListenerBootstrapState();
}

class _ListenerBootstrapState extends State<_ListenerBootstrap> {
  late final Future<DiscoveredServiceEvent> _discovery;
  ListenerGrpc? _listenerGrpc;

  @override
  void initState() {
    super.initState();
    _discovery = widget.engine.discoverService();
  }

  Future<void> _connect(DiscoveredServiceEvent service) async {
    final status = widget.engine.connect(
      host: service.host,
      port: service.port,
    );

    if (status != ListenerStatus.ok) {
      throw StateError(
        'Failed to connect to ${service.host}:${service.port}: ${status.name}',
      );
    }

    final listenerGrpc = ListenerGrpc.connect(host: service.host);
    if (!mounted) {
      await listenerGrpc.close();
      return;
    }

    setState(() => _listenerGrpc = listenerGrpc);
  }

  @override
  void dispose() {
    final listenerGrpc = _listenerGrpc;
    if (listenerGrpc != null) {
      unawaited(listenerGrpc.close());
    }
    widget.engine.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenerGrpc = _listenerGrpc;
    if (listenerGrpc == null) {
      return ServerDiscoveryPage(discovery: _discovery, onConnect: _connect);
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider<PlaybackCubit>(
          create: (_) =>
              PlaybackCubit.connect(widget.engine, listenerGrpc.controlClient),
        ),
        BlocProvider<LibraryCubit>(
          create: (_) => LibraryCubit.connect(listenerGrpc.libraryClient),
        ),
        RepositoryProvider<ArtworkRepository>(
          create: (_) => ArtworkRepository.connect(listenerGrpc.libraryClient),
        ),
      ],
      child: const LibraryScreen(),
    );
  }
}
