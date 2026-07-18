import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/app.dart';
import 'package:listener_front/src/repositories/artwork_repository.dart';
import 'package:listener_front/src/services/listener_grpc.dart';
import 'package:listener_front/src/services/playback_engine.dart';
import 'package:listener_front/src/view_models/library_cubit.dart';
import 'package:listener_front/src/view_models/playback_cubit.dart';

void main() {
  final engine = ListenerEngine.open();
  final status = engine.connect();

  if (status != ListenerStatus.ok) {
    engine.close();
    throw StateError('Failed to connect to playback engine: ${status.name}');
  }

  final listenerGrpc = ListenerGrpc.connect();

  final playbackCubit = BlocProvider<PlaybackCubit>(
    create: (BuildContext context) {
      return PlaybackCubit.connect(engine, listenerGrpc.controlClient);
    },
  );
  final libraryCubit = BlocProvider<LibraryCubit>(
    create: (BuildContext context) {
      return LibraryCubit.connect(listenerGrpc.libraryClient);
    },
  );

  final artworkProvider = RepositoryProvider<ArtworkRepository>(
    create: (BuildContext context) {
      return ArtworkRepository.connect(listenerGrpc.libraryClient);
    },
  );

  runApp(
    MultiBlocProvider(
      providers: [playbackCubit, libraryCubit, artworkProvider],
      child: const MainApp(),
    ),
  );
}
