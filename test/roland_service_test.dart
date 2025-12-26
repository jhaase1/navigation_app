import 'package:test/test.dart';
import '../lib/services/roland_service.dart';

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
    });

    // Note: Actual connection tests require a mock server
    // For now, test validation
    test('setProgram validates input', () {
      expect(() => service.setProgram(-1), throwsArgumentError);
      expect(() => service.setProgram(20), throwsArgumentError);
    });

    test('setFaderLevel validates level', () {
      expect(() => service.setFaderLevel(-1), throwsArgumentError);
      expect(() => service.setFaderLevel(2048), throwsArgumentError);
    });
  });
}