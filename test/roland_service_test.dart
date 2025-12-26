import 'package:test/test.dart';
import 'package:navigation_app/services/roland_service.dart';

void main() {
  group('RolandService', () {
    late RolandService service;

    setUp(() {
      service = RolandService(host: '127.0.0.1', port: 12345); // Mock server needed
    });

    test('constants are correct', () {
      expect(RolandService.defaultPort, 8023);
      expect(RolandService.maxFaderLevel, 2047);
      expect(RolandService.minFaderLevel, 0);
      expect(RolandService.maxAudioLevel, 100);
      expect(RolandService.minAudioLevel, -800);
    });

    test('host validation', () {
      expect(() => RolandService(host: ''), throwsA(isA<ValidationException>()));
      expect(() => RolandService(host: 'invalid@host'), throwsA(isA<ValidationException>()));
      expect(() => RolandService(host: '192.168.1.1'), isNotNull);
    });

    // Note: Actual connection tests require a mock server
    // For now, test validation
    test('setProgram validates input', () {
      expect(() => service.setProgram('INPUT0'), throwsArgumentError);
      expect(() => service.setProgram('INPUT21'), throwsArgumentError);
      expect(() => service.setProgram('INVALID'), throwsArgumentError);
    });

    test('setFaderLevel validates level', () {
      expect(() => service.setFaderLevel(-1), throwsArgumentError);
      expect(() => service.setFaderLevel(2048), throwsArgumentError);
    });

    test('setAudioInputLevel validates level', () {
      expect(() => service.setAudioInputLevel('XLR1', -801), throwsArgumentError);
      expect(() => service.setAudioInputLevel('XLR1', 101), throwsArgumentError);
    });

    test('setSplitPositions validates ranges', () {
      expect(() => service.setSplitPositions('SPLIT1', -501, 0), throwsArgumentError);
      expect(() => service.setSplitPositions('SPLIT1', 0, 501), throwsArgumentError);
      expect(() => service.setSplitPositions('SPLIT1', 0, 0, center: 501), throwsArgumentError);
    });

    test('setPanTilt validates directions', () {
      expect(() => service.setPanTilt('CAMERA1', 'INVALID', 'STOP'), throwsArgumentError);
      expect(() => service.setPanTilt('CAMERA1', 'LEFT', 'INVALID'), throwsArgumentError);
      // Valid call would require connection, but validation passes
      expect(() => service.setPanTilt('CAMERA1', 'LEFT', 'STOP'), throwsA(isA<ConnectionException>()));
    });

    test('disconnect handles gracefully', () {
      // Test that disconnect doesn't crash
      service.disconnect();
    });

    test('parseResponse parses VFL correctly', () {
      final result = service.parseResponseForTest('VFL:1024;ACK;');
      expect(result, isA<FaderLevelResponse>());
      expect((result as FaderLevelResponse).level, 1024);
    });

    test('parseResponse parses CAFC correctly', () {
      final result = service.parseResponseForTest('CAFC:CAMERA1,ON;ACK;');
      expect(result, isA<AutoFocusResponse>());
      expect((result as AutoFocusResponse).camera, 'CAMERA1');
      expect((result as AutoFocusResponse).status, 'ON');
    });

    test('parseResponse returns null for unknown', () {
      final result = service.parseResponseForTest('UNKNOWN:1;ACK;');
      expect(result, isNull);
    });
  });
}
