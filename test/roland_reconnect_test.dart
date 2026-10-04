import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/roland_service.dart';

/// A V-160HD stand-in on loopback: answers the password with Welcome and
/// every command with ACK, and can be unplugged and plugged back in.
class _FakeSwitcher {
  ServerSocket? _server;
  int port = 0;
  final sockets = <Socket>[];
  final commands = <String>[];
  int connections = 0;

  /// When true, the first login is refused, the way a wrong password is.
  bool rejectFirstLogin = false;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    port = _server!.port;
    _server!.listen((s) {
      final n = ++connections;
      sockets.add(s);
      var authed = false;
      s.listen((data) {
        for (final line in utf8.decode(data).split(RegExp(r'\r?\n'))) {
          if (line.trim().isEmpty) continue;
          if (!authed) {
            if (rejectFirstLogin && n == 1) {
              s.write('Authentication error\r\n');
            } else {
              authed = true;
              s.write('Welcome\r\n');
            }
          } else {
            commands.add(line.trim());
            s.write('ACK;\r\n');
          }
        }
      }, onError: (_) {}, onDone: () {});
    });
  }

  /// Pulls the cable: every open connection dies.
  void dropAll() {
    for (final s in sockets) {
      s.destroy();
    }
    sockets.clear();
  }

  /// Powers the switcher off: no new connections either.
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    dropAll();
  }
}

/// Polls until [condition] holds, failing after [within].
Future<void> eventually(bool Function() condition,
    {Duration within = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(within);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $within');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late _FakeSwitcher switcher;
  late RolandService service;
  late List<bool> states;

  setUp(() async {
    switcher = _FakeSwitcher();
    await switcher.start();
    service = RolandService(
      host: '127.0.0.1',
      port: switcher.port,
      commandRetryDelay: const Duration(milliseconds: 10),
    );
    states = [];
    service.connectionChanges.listen(states.add);
  });

  tearDown(() async {
    await service.disconnect();
    await switcher.stop();
  });

  Future<void> connectWithAutoReconnect() async {
    service.setAutoReconnect(true,
        delay: const Duration(milliseconds: 20),
        maxDelay: const Duration(milliseconds: 50));
    await service.connect(retryCount: 0);
    await Future<void>.delayed(Duration.zero); // let "connected" arrive
    states.clear();
  }

  test('a dropped link comes back on its own', () async {
    await connectWithAutoReconnect();

    switcher.dropAll();

    await eventually(() => states.length >= 2);
    expect(states, [false, true]);
    expect(switcher.connections, 2);
  });

  test('commands work after a reconnect', () async {
    await connectWithAutoReconnect();
    switcher.dropAll();
    await eventually(() => states.contains(true));

    await service.cut();

    expect(switcher.commands, contains('CUT;'));
  });

  test('response listeners survive a reconnect', () async {
    await connectWithAutoReconnect();
    var closed = false;
    final sub = service.responseStream
        .listen((_) {}, onError: (_) {}, onDone: () => closed = true);

    switcher.dropAll();
    await eventually(() => states.contains(true));
    await service.cut();

    expect(closed, isFalse,
        reason: 'a dropped link must not end the stream for good');
    await sub.cancel();
  });

  test('keeps trying while the switcher is off, however long', () async {
    await connectWithAutoReconnect();

    await switcher.stop();
    // Well past the old limit of three attempts. Counted rather than timed:
    // a refused connection takes ~1 s on Windows and ~0 s elsewhere.
    await eventually(() => service.reconnectAttempts >= 5,
        within: const Duration(seconds: 30));
    expect(states, [false]);
    await switcher.start();

    await eventually(() => states.length >= 2);
    expect(states.last, isTrue);
  });

  test('a deliberate disconnect stays disconnected', () async {
    await connectWithAutoReconnect();

    await service.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(states, [false]);
    expect(switcher.connections, 1);
  });

  test('a refused login cannot later tear down the connection that worked',
      () async {
    switcher.rejectFirstLogin = true;
    await service.connect(retryCount: 1);
    await Future<void>.delayed(Duration.zero); // let "connected" arrive
    states.clear();

    // The refused attempt's socket finally closes, long after the retry
    // succeeded on a new one.
    switcher.sockets.first.destroy();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(states, isEmpty);
    await service.cut();
    expect(switcher.commands, contains('CUT;'));
  });
}
