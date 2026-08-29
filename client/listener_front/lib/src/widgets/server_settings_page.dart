import 'package:flutter/material.dart';
import 'package:listener_front/src/models/server_endpoint.dart';
import 'package:listener_front/src/theme.dart';

typedef ConnectToEndpoint = Future<void> Function(ServerEndpoint endpoint);
typedef FindServers = Future<void> Function();

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({
    super.key,
    required this.currentServer,
    required this.onConnect,
    required this.onFindServers,
  });

  final ServerEndpoint currentServer;
  final ConnectToEndpoint onConnect;
  final FindServers onFindServers;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  bool _connecting = false;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController();
    _portController = TextEditingController(
      text: widget.currentServer.port.toString(),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting || !_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _connecting = true;
      _connectionError = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final endpoint = ServerEndpoint.manual(
      host: _hostController.text,
      port: int.parse(_portController.text),
    );

    try {
      await widget.onConnect(endpoint);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _connectionError = error.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _findServers() async {
    if (_connecting) return;

    final navigator = Navigator.of(context);
    navigator.pop();
    await widget.onFindServers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server settings'),
        backgroundColor: panelColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'CONNECTED SERVER',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 12),
                _CurrentServerCard(server: widget.currentServer),
                const SizedBox(height: 36),
                Text(
                  'Connect to a different server',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter an address directly, or search your local network.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: mutedColor),
                ),
                const SizedBox(height: 22),
                Form(
                  key: _formKey,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('server-host-field'),
                          controller: _hostController,
                          enabled: !_connecting,
                          decoration: const InputDecoration(
                            labelText: 'Hostname or IP address',
                            hintText: 'studio.local',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter a server address';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          key: const Key('server-port-field'),
                          controller: _portController,
                          enabled: !_connecting,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onFieldSubmitted: (_) => _connect(),
                          validator: (value) {
                            final port = int.tryParse(value ?? '');
                            if (port == null || port < 1 || port > 0xffff) {
                              return 'Invalid port';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (_connectionError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _connectionError!,
                    key: const Key('server-settings-connection-error'),
                    style: const TextStyle(color: Color(0xFFFF8A80)),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const Key('connect-address-button'),
                  onPressed: _connecting ? null : _connect,
                  icon: _connecting
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.link_rounded),
                  label: Text(_connecting ? 'Connecting…' : 'Connect'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: accentColor,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('find-servers-button'),
                  onPressed: _connecting ? null : _findServers,
                  icon: const Icon(Icons.wifi_find_rounded),
                  label: const Text('Search local network'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: textColor,
                    side: const BorderSide(color: lineColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentServerCard extends StatelessWidget {
  const _CurrentServerCard({required this.server});

  final ServerEndpoint server;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('current-server-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panelColor,
        border: Border.all(color: lineColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.dns_outlined, color: textColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.displayName,
                  style: const TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(server.address, style: const TextStyle(color: mutedColor)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.check_circle_rounded, color: greenColor, size: 20),
        ],
      ),
    );
  }
}
