// Copyright (c) 2026 Listener contributors. All rights reserved.

import 'package:listener_engine/listener_engine.dart';
import 'package:test/test.dart';

void main() {
  test('loads the bundled native engine and validates its ABI', () {
    final engine = ListenerEngine.open();
    addTearDown(engine.close);

    expect(engine.abiVersion, 1);
  });

  test('maps unknown native status codes to unexpected', () {
    expect(ListenerStatus.fromCode(254), ListenerStatus.unexpected);
  });

  test('enumerates local output devices', () {
    final engine = ListenerEngine.open();
    addTearDown(engine.close);

    final devices = engine.outputDevices();
    for (final device in devices) {
      expect(device.id, isNotEmpty);
      expect(device.name, isNotEmpty);
      expect(device.capabilities.supportsExclusiveMode, isA<bool>());
    }
    expect(
      devices.where((device) => device.isDefault).length,
      lessThanOrEqualTo(1),
    );
  });

  test('selects an enumerated output and restores the system default', () {
    final engine = ListenerEngine.open();
    addTearDown(engine.close);

    final devices = engine.outputDevices();
    if (devices.isNotEmpty) {
      expect(engine.selectOutputDevice(devices.first.id), ListenerStatus.ok);
    }
    expect(engine.selectOutputDevice(null), ListenerStatus.ok);
  });

  test('configures portable output behavior', () {
    final engine = ListenerEngine.open();
    addTearDown(engine.close);

    expect(
      engine.configureOutput(const AudioOutputConfiguration()),
      ListenerStatus.ok,
    );
  });
}
