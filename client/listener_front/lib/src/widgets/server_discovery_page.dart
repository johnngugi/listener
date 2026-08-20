import 'dart:async';

import 'package:flutter/material.dart';
import 'package:listener_front/src/services/playback_engine_event.dart';
import 'package:listener_front/src/theme.dart';

typedef ConnectToServer = Future<void> Function(DiscoveredServiceEvent service);

class ServerDiscoveryPage extends StatefulWidget {
  const ServerDiscoveryPage({
    super.key,
    required this.discovery,
    required this.onConnect,
  });

  final Future<DiscoveredServiceEvent> discovery;
  final ConnectToServer onConnect;

  @override
  State<ServerDiscoveryPage> createState() => _ServerDiscoveryPageState();
}

class _ServerDiscoveryPageState extends State<ServerDiscoveryPage> {
  late Future<DiscoveredServiceEvent> _discovery;
  bool _connecting = false;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _discovery = widget.discovery;
  }

  @override
  void didUpdateWidget(covariant ServerDiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.discovery, widget.discovery)) {
      _discovery = widget.discovery;
      _connectionError = null;
    }
  }

  Future<void> _connect(DiscoveredServiceEvent service) async {
    if (_connecting) return;

    setState(() {
      _connecting = true;
      _connectionError = null;
    });

    try {
      await widget.onConnect(service);
    } catch (error) {
      if (mounted) {
        setState(() => _connectionError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _Atmosphere(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    children: [
                      const _PageIntroduction(),
                      const SizedBox(height: 46),
                      FutureBuilder<DiscoveredServiceEvent>(
                        future: _discovery,
                        builder: (context, snapshot) {
                          final Widget content;

                          if (snapshot.hasData) {
                            content = _FoundServer(
                              key: const ValueKey('found'),
                              service: snapshot.requireData,
                              connecting: _connecting,
                              connectionError: _connectionError,
                              onConnect: () => _connect(snapshot.requireData),
                            );
                          } else if (snapshot.hasError) {
                            content = _DiscoveryError(
                              key: const ValueKey('error'),
                              error: snapshot.error,
                            );
                          } else {
                            content = const _Searching(
                              key: ValueKey('searching'),
                            );
                          }

                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 420),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: content,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageIntroduction extends StatelessWidget {
  const _PageIntroduction();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            border: Border.all(color: accentColor.withValues(alpha: 0.36)),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.graphic_eq_rounded, color: accentColor),
        ),
        const SizedBox(height: 22),
        Text(
          'CONNECT TO LISTENER',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 13),
        Text(
          'Find your music server',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'Listener is looking for a server on your local network. '
            'Keep the server running and connected to the same network.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: mutedColor, height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Searching for a Listener server',
      child: Column(
        children: [
          const _SignalMark(),
          const SizedBox(height: 28),
          Text(
            'Searching your network',
            key: const Key('server-searching-label'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'This usually takes only a moment.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: mutedColor),
          ),
        ],
      ),
    );
  }
}

class _SignalMark extends StatefulWidget {
  const _SignalMark();

  @override
  State<_SignalMark> createState() => _SignalMarkState();
}

class _SignalMarkState extends State<_SignalMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 104,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _SignalPainter(_controller.value),
            child: child,
          );
        },
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: panelColor,
              border: Border.all(color: lineColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.36),
                  blurRadius: 24,
                ),
              ],
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: textColor,
              size: 29,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalPainter extends CustomPainter {
  const _SignalPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    for (var ring = 0; ring < 2; ring++) {
      final ringProgress = (progress + ring * 0.5) % 1;
      final radius = 30 + ringProgress * 21;
      final opacity = (1 - ringProgress) * 0.42;
      final paint = Paint()
        ..color = accentColor.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignalPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _FoundServer extends StatelessWidget {
  const _FoundServer({
    super.key,
    required this.service,
    required this.connecting,
    required this.connectionError,
    required this.onConnect,
  });

  final DiscoveredServiceEvent service;
  final bool connecting;
  final String? connectionError;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Listener server found: ${_displayName(service.fullName)}',
      child: Container(
        key: const Key('found-server-card'),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: panelColor.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: lineColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.26),
              blurRadius: 36,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final details = _ServerDetails(service: service);
            final action = SizedBox(
              width: compact ? double.infinity : 176,
              height: 46,
              child: FilledButton(
                key: const Key('connect-server-button'),
                onPressed: connecting ? null : onConnect,
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: accentColor.withValues(alpha: 0.46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: connecting
                      ? const SizedBox.square(
                          key: ValueKey('connecting'),
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Connect',
                          key: ValueKey('connect'),
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact) ...[
                  details,
                  const SizedBox(height: 22),
                  action,
                ] else
                  Row(
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 28),
                      action,
                    ],
                  ),
                if (connectionError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    connectionError!,
                    key: const Key('server-connection-error'),
                    textAlign: compact ? TextAlign.center : TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFFF8A80),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ServerDetails extends StatelessWidget {
  const _ServerDetails({required this.service});

  final DiscoveredServiceEvent service;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: backgroundColor.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: lineColor),
          ),
          child: const Icon(Icons.dns_outlined, color: textColor, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayName(service.fullName),
                key: const Key('found-server-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${_displayHost(service.host)}:${service.port}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: mutedColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ReadyDot(),
                  SizedBox(width: 7),
                  Text(
                    'Ready',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadyDot extends StatelessWidget {
  const _ReadyDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: greenColor,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _DiscoveryError extends StatelessWidget {
  const _DiscoveryError({super.key, required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Server discovery failed',
      child: Container(
        key: const Key('server-discovery-error'),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: panelColor.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: lineColor),
        ),
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded, color: mutedColor, size: 30),
            const SizedBox(height: 14),
            Text(
              'Could not search the network',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: mutedColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _Atmosphere extends StatelessWidget {
  const _Atmosphere();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.95,
          colors: [Color(0xFF1B1B27), backgroundColor],
          stops: [0, 0.72],
        ),
      ),
      child: CustomPaint(painter: _GridPainter()),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.018)
      ..strokeWidth = 1;

    const spacing = 46.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _displayName(String fullName) {
  const serviceMarker = '._lstn.';
  final markerIndex = fullName.indexOf(serviceMarker);
  return markerIndex == -1 ? fullName : fullName.substring(0, markerIndex);
}

String _displayHost(String host) {
  return host.endsWith('.') ? host.substring(0, host.length - 1) : host;
}
