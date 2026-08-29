import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/models/server_endpoint.dart';
import 'package:listener_front/src/services/last_server_store.dart';

void main() {
  group('LastServerPreferences', () {
    test('returns null when no server has been saved', () async {
      final preferences = _MemoryStringPreferences();
      final store = LastServerPreferences(preferences);

      expect(await store.load(), isNull);
    });

    test('round-trips the last connected server', () async {
      final preferences = _MemoryStringPreferences();
      final store = LastServerPreferences(preferences);
      const server = ServerEndpoint(
        fullName: 'Studio._lstn._tcp.local.',
        host: 'studio.local.',
        port: 5778,
      );

      await store.save(server);
      final restored = await store.load();

      expect(restored, isNotNull);
      expect(restored!.fullName, server.fullName);
      expect(restored.host, server.host);
      expect(restored.port, server.port);
      expect(restored.displayName, 'Studio');
      expect(restored.address, 'studio.local:5778');
    });

    test('ignores malformed or invalid saved data', () async {
      for (final value in [
        'not json',
        '[]',
        '{"fullName":"Studio","host":"","port":5778}',
        '{"fullName":"Studio","host":"studio.local","port":70000}',
      ]) {
        final store = LastServerPreferences(
          _MemoryStringPreferences(value: value),
        );

        expect(await store.load(), isNull, reason: value);
      }
    });
  });
}

class _MemoryStringPreferences implements StringPreferenceStore {
  _MemoryStringPreferences({this.value});

  String? value;

  @override
  Future<String?> getString(String key) async => value;

  @override
  Future<void> setString(String key, String value) async {
    this.value = value;
  }
}
