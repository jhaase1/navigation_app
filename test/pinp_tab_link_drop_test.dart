import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/roland_service.dart';
import 'package:navigation_app/widgets/pinp_tab.dart';

void main() {
  testWidgets('a dropped switcher link is not an unhandled error in PinP',
      (tester) async {
    late ServerSocket server;
    final sockets = <Socket>[];
    late RolandService service;

    await tester.runAsync(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((s) {
        sockets.add(s);
        s.listen((data) {
          for (final line in utf8.decode(data).split(RegExp(r'\r?\n'))) {
            if (line.trim().isNotEmpty) s.write('Welcome\r\n');
          }
        }, onError: (_) {});
      });
      service = RolandService(host: '127.0.0.1', port: server.port);
      await service.connect();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PinPTab(
          rolandConnected: ValueNotifier(true),
          onRolandResponse: (_) {},
          rolandService: service,
        ),
      ),
    ));

    await tester.runAsync(() async {
      for (final s in sockets) {
        s.destroy();
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    // An error nobody listens for fails the test on its own; this catches
    // one the framework reported instead.
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      service.dispose();
      await server.close();
    });
  });
}
