import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/models/server_endpoint.dart';
import 'package:listener_front/src/widgets/server_settings_page.dart';

void main() {
  testWidgets('shows the active server and connects to a direct address', (
    tester,
  ) async {
    ServerEndpoint? requestedServer;

    await tester.pumpWidget(
      _SettingsTestApp(onConnect: (server) async => requestedServer = server),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('current-server-card')), findsOneWidget);
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('studio.local:5778'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('server-host-field')),
      'office.local',
    );
    await tester.enterText(find.byKey(const Key('server-port-field')), '6000');
    await tester.tap(find.byKey(const Key('connect-address-button')));
    await tester.pumpAndSettle();

    expect(requestedServer, isNotNull);
    expect(requestedServer!.host, 'office.local');
    expect(requestedServer!.port, 6000);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('validates the direct server address', (tester) async {
    await tester.pumpWidget(const _SettingsTestApp());
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('server-port-field')), '70000');
    await tester.tap(find.byKey(const Key('connect-address-button')));
    await tester.pump();

    expect(find.text('Enter a server address'), findsOneWidget);
    expect(find.text('Invalid port'), findsOneWidget);
  });

  testWidgets('returns to discovery when local search is selected', (
    tester,
  ) async {
    var searched = false;
    await tester.pumpWidget(
      _SettingsTestApp(onFindServers: () async => searched = true),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('find-servers-button')));
    await tester.pumpAndSettle();

    expect(searched, isTrue);
    expect(find.text('Open settings'), findsOneWidget);
  });
}

class _SettingsTestApp extends StatelessWidget {
  const _SettingsTestApp({this.onConnect, this.onFindServers});

  final ConnectToEndpoint? onConnect;
  final FindServers? onFindServers;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ServerSettingsPage(
                        currentServer: _currentServer,
                        onConnect: onConnect ?? (_) async {},
                        onFindServers: onFindServers ?? () async {},
                      ),
                    ),
                  );
                },
                child: const Text('Open settings'),
              ),
            ),
          );
        },
      ),
    );
  }
}

const _currentServer = ServerEndpoint(
  fullName: 'Studio._lstn._tcp.local.',
  host: 'studio.local.',
  port: 5778,
);
