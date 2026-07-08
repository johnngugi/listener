import 'package:flutter/material.dart';
import 'package:listener_front/src/theme.dart';
import 'package:listener_front/src/widgets/now_playing_bar.dart';
import 'package:listener_front/src/widgets/sidebar.dart';
import 'package:listener_front/src/widgets/track_library.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

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
      home: const LibraryScreen(),
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Sidebar(),
                Expanded(child: TrackLibrary()),
              ],
            ),
          ),
          NowPlayingBar(),
        ],
      ),
    );
  }
}
