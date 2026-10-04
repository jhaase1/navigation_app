import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/roland_service.dart';

/// A switcher on loopback whose acknowledgements the test hands out by
/// hand, so a slow, missing or late ACK can be staged exactly.
class _ScriptedSwitcher {
  late ServerSocket _server;
  Socket? _client;
  final commands = <String>[];

  /// When true, commands are recorded but not acknowledged until [ack].
  bool holdAcks = false;

  /// When true, the connection is cut the moment a command arrives.
  bool dropOnCommand = false;

  int get port => _server.port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((s) {
      _client = s;
      var authed = false;
      s.listen((data) {
        for (final line in utf8.decode(data).split(RegExp(r'\r?\n'))) {
          if (line.trim().isEmpty) continue;
          if (!authed) {
            authed = true;
            s.write('Welcome\r\n');
            continue;
          }
          commands.add(line.trim());
          if (dropOnCommand) {
            s.destroy();
          } else if (!holdAcks) {
            s.write('ACK;\r\n');
          }
        }
      }, onError: (_) {}, onDone: () {});
    });
  }

  /// Sends one acknowledgement now.
  void ack() => _client!.write('ACK;\r\n');

  Future<void> stop() async {
    _client?.destroy();
    await _server.close();
  }
}

void main() {
  late _ScriptedSwitcher switcher;
  late RolandService service;
  const ackTimeout = Duration(milliseconds: 300);

  setUp(() async {
    switcher = _ScriptedSwitcher();
    await switcher.start();
    service = RolandService(
      host: '127.0.0.1',
      port: switcher.port,
      ackTimeout: ackTimeout,
      commandRetryDelay: const Duration(milliseconds: 10),
    );
    await service.connect(retryCount: 0);
  });

  tearDown(() async {
    await service.disconnect();
    await switcher.stop();
  });

  test('an unacknowledged command fails once and is never sent again',
      () async {
    switcher.holdAcks = true;
    final started = DateTime.now();

    await expectLater(service.cut(), throwsA(anything));

    // Sending CUT twice swaps program and preview twice: the wrong shot ends
    // up on air while every retry "succeeds".
    expect(switcher.commands, ['CUT;']);
    expect(DateTime.now().difference(started), lessThan(ackTimeout * 3),
        reason: 'one timeout, not one per retry');
  });

  test('a late acknowledgement is not credited to the next command',
      () async {
    switcher.holdAcks = true;
    await expectLater(service.cut(), throwsA(anything));

    var secondDone = false;
    final second = service.setProgram('HDMI1')
        .then((_) => secondDone = true);
    await _until(() => switcher.commands.length == 2);
    // CUT's acknowledgement finally turns up.
    switcher.ack();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(secondDone, isFalse,
        reason: "CUT's late ACK must not complete PGM:HDMI1");

    switcher.ack();
    await second;
    expect(secondDone, isTrue);
  });

  test('a command in flight when the link drops fails at once', () async {
    switcher.dropOnCommand = true;
    final started = DateTime.now();

    await expectLater(service.cut(), throwsA(anything));

    expect(DateTime.now().difference(started), lessThan(ackTimeout),
        reason: 'the socket is gone; waiting out timeouts tells nobody anything');
  });

  test('commands still flow after a failed one', () async {
    switcher.holdAcks = true;
    await expectLater(service.cut(), throwsA(anything));
    switcher.ack(); // the late one, absorbed by its own expired slot
    switcher.holdAcks = false;

    await service.setProgram('HDMI1');

    expect(switcher.commands.last, 'PGM:HDMI1;');
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
