import 'package:flutter/material.dart';
import 'package:listener_engine/listener_engine.dart';
import 'package:listener_front/src/app.dart';
import 'package:listener_front/src/services/last_server_store.dart';
import 'package:listener_front/src/widgets/listener_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MainApp(
      home: ListenerBootstrap(
        engineFactory: ListenerEngine.open,
        lastServerStore: LastServerPreferences(),
      ),
    ),
  );
}
