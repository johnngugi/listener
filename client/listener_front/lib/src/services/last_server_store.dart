import 'dart:convert';

import 'package:listener_front/src/models/server_endpoint.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LastServerStore {
  Future<ServerEndpoint?> load();

  Future<void> save(ServerEndpoint server);
}

abstract interface class StringPreferenceStore {
  Future<String?> getString(String key);

  Future<void> setString(String key, String value);
}

final class SharedPreferencesStringStore implements StringPreferenceStore {
  SharedPreferencesStringStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) {
    return _preferences.setString(key, value);
  }
}

final class LastServerPreferences implements LastServerStore {
  LastServerPreferences([StringPreferenceStore? preferences])
    : _preferences = preferences ?? SharedPreferencesStringStore();

  static const _serverKey = 'listener.last_server';

  final StringPreferenceStore _preferences;

  @override
  Future<ServerEndpoint?> load() async {
    final encoded = await _preferences.getString(_serverKey);
    if (encoded == null) return null;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;

      final fullName = decoded['fullName'];
      final host = decoded['host'];
      final port = decoded['port'];
      if (fullName is! String ||
          fullName.isEmpty ||
          host is! String ||
          host.isEmpty ||
          port is! int ||
          port < 1 ||
          port > 0xffff) {
        return null;
      }

      return ServerEndpoint(fullName: fullName, host: host, port: port);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(ServerEndpoint server) {
    return _preferences.setString(
      _serverKey,
      jsonEncode({
        'fullName': server.fullName,
        'host': server.host,
        'port': server.port,
      }),
    );
  }
}
