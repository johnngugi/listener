import 'package:flutter/material.dart';
import 'package:listener_front/src/models/server_endpoint.dart';
import 'package:listener_front/src/theme.dart';
import 'package:listener_front/src/widgets/now_playing_bar.dart';
import 'package:listener_front/src/widgets/server_settings_page.dart';
import 'package:listener_front/src/widgets/sidebar.dart';
import 'package:listener_front/src/widgets/track_library.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.home = const LibraryScreen()});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: const ColorScheme.dark(primary: accentColor),
        fontFamily: 'Helvetica',
      ),
      home: home,
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    this.currentServer,
    this.onConnectServer,
    this.onFindServers,
  });

  static const sidebarBreakpoint = 1100.0;

  final ServerEndpoint? currentServer;
  final ConnectToEndpoint? onConnectServer;
  final FindServers? onFindServers;

  void _openServerSettings(BuildContext context) {
    final currentServer = this.currentServer;
    final onConnectServer = this.onConnectServer;
    final onFindServers = this.onFindServers;
    if (currentServer == null ||
        onConnectServer == null ||
        onFindServers == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerSettingsPage(
          currentServer: currentServer,
          onConnect: onConnectServer,
          onFindServers: onFindServers,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidebar = constraints.maxWidth >= sidebarBreakpoint;

        return Scaffold(
          drawer: showSidebar
              ? null
              : Drawer(
                  width: 260,
                  backgroundColor: panelColor,
                  child: SafeArea(
                    child: Sidebar(
                      onSettings: currentServer == null
                          ? null
                          : () => _openServerSettings(context),
                    ),
                  ),
                ),
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (showSidebar)
                      Sidebar(
                        onSettings: currentServer == null
                            ? null
                            : () => _openServerSettings(context),
                      ),
                    Expanded(
                      child: TrackLibrary(showSidebarButton: !showSidebar),
                    ),
                  ],
                ),
              ),
              const NowPlayingBar(),
            ],
          ),
        );
      },
    );
  }
}
