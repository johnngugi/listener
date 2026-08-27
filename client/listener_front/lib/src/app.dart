import 'package:flutter/material.dart';
import 'package:listener_front/src/theme.dart';
import 'package:listener_front/src/widgets/now_playing_bar.dart';
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
  const LibraryScreen({super.key});

  static const sidebarBreakpoint = 1100.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidebar = constraints.maxWidth >= sidebarBreakpoint;

        return Scaffold(
          drawer: showSidebar
              ? null
              : const Drawer(
                  width: 260,
                  backgroundColor: panelColor,
                  child: SafeArea(child: Sidebar()),
                ),
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (showSidebar) const Sidebar(),
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
