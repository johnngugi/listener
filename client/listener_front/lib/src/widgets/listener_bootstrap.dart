import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_engine/listener_engine.dart';
import 'package:listener_front/src/app.dart';
import 'package:listener_front/src/models/server_endpoint.dart';
import 'package:listener_front/src/repositories/artwork_repository.dart';
import 'package:listener_front/src/services/last_server_store.dart';
import 'package:listener_front/src/services/listener_grpc.dart';
import 'package:listener_front/src/theme.dart';
import 'package:listener_front/src/view_models/library_cubit.dart';
import 'package:listener_front/src/view_models/output_device_cubit.dart';
import 'package:listener_front/src/view_models/playback_cubit.dart';
import 'package:listener_front/src/widgets/server_discovery_page.dart';

typedef ListenerEngineFactory = ListenerEngine Function();

class ListenerBootstrap extends StatefulWidget {
  const ListenerBootstrap({
    super.key,
    required this.engineFactory,
    required this.lastServerStore,
  });

  final ListenerEngineFactory engineFactory;
  final LastServerStore lastServerStore;

  @override
  State<ListenerBootstrap> createState() => _ListenerBootstrapState();
}

class _ListenerBootstrapState extends State<ListenerBootstrap> {
  late ListenerEngine _engine;
  ListenerGrpc? _listenerGrpc;
  ServerEndpoint? _currentServer;
  Future<DiscoveredServiceEvent>? _discovery;
  ServerEndpoint? _connectingTo;
  String? _discoveryNotice;

  @override
  void initState() {
    super.initState();
    _engine = widget.engineFactory();
    unawaited(_restoreLastServer());
  }

  Future<void> _restoreLastServer() async {
    ServerEndpoint? lastServer;
    try {
      lastServer = await widget.lastServerStore.load();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'listener server preferences',
          context: ErrorDescription('while loading the last server'),
        ),
      );
    }

    if (!mounted) return;
    if (lastServer == null) {
      _beginDiscovery();
      return;
    }

    setState(() => _connectingTo = lastServer);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      await _establishConnection(lastServer);
    } catch (_) {
      if (mounted) {
        _beginDiscovery(
          notice:
              'We couldn’t reach ${lastServer.displayName}, so we’re looking '
              'for another server.',
        );
      }
    }
  }

  Future<void> _establishConnection(ServerEndpoint endpoint) async {
    final status = _engine.connect(host: endpoint.host, port: endpoint.port);
    if (status != ListenerStatus.ok) {
      throw StateError(
        'Failed to connect to ${endpoint.address}: ${status.name}',
      );
    }

    final listenerGrpc = ListenerGrpc.connect(host: endpoint.host);
    if (!mounted) {
      await listenerGrpc.close();
      return;
    }

    setState(() {
      _listenerGrpc = listenerGrpc;
      _currentServer = endpoint;
      _connectingTo = null;
      _discovery = null;
      _discoveryNotice = null;
    });

    await _rememberServer(endpoint);
  }

  Future<void> _connectDiscovered(DiscoveredServiceEvent service) {
    return _establishConnection(ServerEndpoint.fromDiscovery(service));
  }

  void _beginDiscovery({String? notice}) {
    Future<DiscoveredServiceEvent> discovery;
    try {
      discovery = _engine.discoverService();
    } catch (error, stackTrace) {
      discovery = Future<DiscoveredServiceEvent>.error(error, stackTrace);
    }

    setState(() {
      _listenerGrpc = null;
      _currentServer = null;
      _connectingTo = null;
      _discovery = discovery;
      _discoveryNotice = notice;
    });
  }

  Future<void> _replaceEngine() async {
    final previousEngine = _engine;
    final previousGrpc = _listenerGrpc;

    setState(() {
      _listenerGrpc = null;
      _currentServer = null;
      _discovery = null;
      _discoveryNotice = null;
      _connectingTo = null;
    });

    await WidgetsBinding.instance.endOfFrame;
    if (previousGrpc != null) await previousGrpc.close();
    previousEngine.close();

    if (!mounted) return;
    _engine = widget.engineFactory();
  }

  Future<void> _connectDifferentServer(ServerEndpoint endpoint) async {
    final nextEngine = widget.engineFactory();
    final status = nextEngine.connect(host: endpoint.host, port: endpoint.port);
    if (status != ListenerStatus.ok) {
      nextEngine.close();
      throw StateError(
        'Failed to connect to ${endpoint.address}: ${status.name}',
      );
    }

    final nextGrpc = ListenerGrpc.connect(host: endpoint.host);
    if (!mounted) {
      await nextGrpc.close();
      nextEngine.close();
      return;
    }

    final previousEngine = _engine;
    final previousGrpc = _listenerGrpc;
    setState(() {
      _engine = nextEngine;
      _listenerGrpc = nextGrpc;
      _currentServer = endpoint;
      _discovery = null;
      _discoveryNotice = null;
      _connectingTo = null;
    });

    await WidgetsBinding.instance.endOfFrame;
    if (previousGrpc != null) await previousGrpc.close();
    previousEngine.close();
    await _rememberServer(endpoint);
  }

  Future<void> _findDifferentServer() async {
    await _replaceEngine();
    if (mounted) _beginDiscovery();
  }

  Future<void> _rememberServer(ServerEndpoint endpoint) async {
    try {
      await widget.lastServerStore.save(endpoint);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'listener server preferences',
          context: ErrorDescription('while saving the connected server'),
        ),
      );
    }
  }

  @override
  void dispose() {
    final listenerGrpc = _listenerGrpc;
    if (listenerGrpc != null) unawaited(listenerGrpc.close());
    _engine.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenerGrpc = _listenerGrpc;
    final currentServer = _currentServer;
    if (listenerGrpc != null && currentServer != null) {
      return MultiBlocProvider(
        key: ObjectKey(_engine),
        providers: [
          BlocProvider<PlaybackCubit>(
            create: (_) =>
                PlaybackCubit.connect(_engine, listenerGrpc.controlClient),
          ),
          BlocProvider<OutputDeviceCubit>(
            create: (context) =>
                OutputDeviceCubit(_engine, context.read<PlaybackCubit>()),
          ),
          BlocProvider<LibraryCubit>(
            create: (_) => LibraryCubit.connect(listenerGrpc.libraryClient),
          ),
          RepositoryProvider<ArtworkRepository>(
            create: (_) =>
                ArtworkRepository.connect(listenerGrpc.libraryClient),
          ),
        ],
        child: LibraryScreen(
          currentServer: currentServer,
          onConnectServer: _connectDifferentServer,
          onFindServers: _findDifferentServer,
        ),
      );
    }

    final discovery = _discovery;
    if (discovery != null) {
      return ServerDiscoveryPage(
        discovery: discovery,
        onConnect: _connectDiscovered,
        notice: _discoveryNotice,
      );
    }

    return _ConnectionProgressPage(server: _connectingTo);
  }
}

class _ConnectionProgressPage extends StatelessWidget {
  const _ConnectionProgressPage({this.server});

  final ServerEndpoint? server;

  @override
  Widget build(BuildContext context) {
    final server = this.server;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              server == null
                  ? 'Preparing Listener…'
                  : 'Connecting to ${server.displayName}…',
              key: const Key('server-connection-progress'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
