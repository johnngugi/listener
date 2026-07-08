import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/app.dart';
import 'package:listener_front/src/services/playback_engine.dart';
import 'package:listener_front/src/view_models/playback_cubit.dart';

void main() {
  final engine = ListenerEngine.open();
  final status = engine.connect();

  if (status != ListenerStatus.ok) {
    engine.close();
    throw StateError('Failed to connect to playback engine: ${status.name}');
  }

  runApp(
    BlocProvider(
      create: (_) => PlaybackCubit.connect(engine),
      child: const MainApp(),
    ),
  );
}
