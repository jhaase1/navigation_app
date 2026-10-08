import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/roland_service.dart';

void main() {
  group('RolandService connection state', () {
    late ServerSocket server;
    late Socket serverSide;
    late RolandService service;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<Socket>();
      server.listen((s) {
        accepted.complete(s);
        s.listen((_) => s.write('Welcome\r\n'));
      });
      service = RolandService(host: '127.0.0.1', port: server.port);
      await service.connect(retryCount: 0);
      serverSide = await accepted.future;
    });

    tearDown(() async {
      await server.close();
    });

    test('reports false when the switcher drops the socket', () async {
      final states = <bool>[];
      final sub = service.connectionChanges.listen(states.add);

      await serverSide.close();
      serverSide.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(states, [false]);
      await sub.cancel();
    });

    test('reports false on a deliberate disconnect', () async {
      final states = <bool>[];
      final sub = service.connectionChanges.listen(states.add);

      await service.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states, [false]);
      await sub.cancel();
    });
  });
}
