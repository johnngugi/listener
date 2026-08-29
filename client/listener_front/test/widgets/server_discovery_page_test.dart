import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listener_engine/listener_engine.dart';
import 'package:listener_front/src/widgets/server_discovery_page.dart';

void main() {
  testWidgets('shows searching and then the discovered server', (tester) async {
    final discovery = Completer<DiscoveredServiceEvent>();
    DiscoveredServiceEvent? connectedService;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ServerDiscoveryPage(
          discovery: discovery.future,
          onConnect: (service) async => connectedService = service,
        ),
      ),
    );

    expect(find.byKey(const Key('server-searching-label')), findsOneWidget);
    expect(find.byKey(const Key('found-server-card')), findsNothing);

    const service = DiscoveredServiceEvent(
      fullName: 'Studio._lstn._tcp.local.',
      host: 'studio.local.',
      port: 5778,
    );
    discovery.complete(service);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('found-server-card')), findsOneWidget);
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('studio.local:5778'), findsOneWidget);

    await tester.tap(find.byKey(const Key('connect-server-button')));
    await tester.pumpAndSettle();

    expect(connectedService, same(service));
  });

  testWidgets('shows discovery errors', (tester) async {
    final discovery = Completer<DiscoveredServiceEvent>();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ServerDiscoveryPage(
          discovery: discovery.future,
          onConnect: (_) async {},
        ),
      ),
    );

    discovery.completeError(StateError('Bonjour unavailable'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-discovery-error')), findsOneWidget);
    expect(find.textContaining('Bonjour unavailable'), findsOneWidget);
  });

  testWidgets('explains why discovery followed an automatic reconnect', (
    tester,
  ) async {
    final discovery = Completer<DiscoveredServiceEvent>();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ServerDiscoveryPage(
          discovery: discovery.future,
          onConnect: (_) async {},
          notice: 'The saved server is unavailable.',
        ),
      ),
    );

    expect(find.byKey(const Key('server-discovery-notice')), findsOneWidget);
    expect(find.text('The saved server is unavailable.'), findsOneWidget);
  });
}
