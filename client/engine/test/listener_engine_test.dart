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
}
