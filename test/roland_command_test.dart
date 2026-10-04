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
  void ack() => send('ACK;');

  /// Sends one raw reply line now.
  void send(String line) => _client!.write('$line\r\n');

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

  test('a command in flight when the link drops fails at once', () async {
    switcher.dropOnCommand = true;
    final started = DateTime.now();

    await expectLater(service.cut(), throwsA(anything));

    expect(DateTime.now().difference(started), lessThan(ackTimeout),
        reason: 'the socket is gone; waiting out timeouts tells nobody anything');
  });

  test('a lost acknowledgement does not fail every command after it',
      () async {
    // Replies carry no id. Had the lost one's slot stayed queued, each later
    // ACK would complete the slot before it, so every later command would
    // run on the switcher yet report "no reply" — and a second tap on a
    // "failed" CUT puts the wrong shot on air.
    final links = <bool>[];
    service.connectionChanges.listen(links.add);
    service.setAutoReconnect(true,
        delay: const Duration(milliseconds: 20),
        maxDelay: const Duration(milliseconds: 20));
    switcher.holdAcks = true;
    await expectLater(service.cut(), throwsA(anything));
    switcher.holdAcks = false;

    await _until(() => links.isNotEmpty && links.last);
    await service.setProgram('HDMI1');
    await service.setProgram('HDMI2');

    expect(switcher.commands, ['CUT;', 'PGM:HDMI1;', 'PGM:HDMI2;']);
  });

  test('one reply that fails to parse completes one command, not three',
      () async {
    switcher.holdAcks = true;
    var done = 0;
    final pending = [
      service.getFaderLevel().then((_) => done++),
      service.setProgram('HDMI1').then((_) => done++),
      service.setProgram('HDMI2').then((_) => done++),
    ];
    await _until(() => switcher.commands.length == 3);

    switcher.send('VFL:garbled;');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(done, 1, reason: 'the two unanswered commands are still waiting');

    switcher.ack();
    switcher.ack();
    await Future.wait(pending);
    expect(done, 3);
  });

  test('a refused command fails alone; the next lines up with its own reply',
      () async {
    // A NACKed macro reported as done is a cue that silently did nothing;
    // a NACK that shifted later replies would credit each to the wrong
    // command.
    final links = <bool>[];
    service.connectionChanges.listen(links.add);
    switcher.holdAcks = true;
    final macro = service.executeMacro(3);
    await _until(() => switcher.commands.length == 1);

    switcher.send('NACK;');
    await expectLater(macro, throwsA(isA<CommandException>()));

    var cutDone = false;
    final cut = service.cut().then((_) => cutDone = true);
    await _until(() => switcher.commands.length == 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cutDone, isFalse, reason: 'no reply for CUT has arrived yet');
    switcher.ack();
    await cut;

    expect(links, isEmpty, reason: 'a refusal is not a dead link');
  });

  test('an ERR reply is a refusal, not a success', () async {
    // Roland's LAN protocol may report a refused command as `ERR:n;`. It
    // contains a colon like a query answer, so it used to complete the
    // command as done: a refused cue with a green check.
    switcher.holdAcks = true;
    final macro = service.executeMacro(5);
    await _until(() => switcher.commands.length == 1);

    switcher.send('ERR:4;');

    await expectLater(macro, throwsA(isA<CommandException>()));
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
