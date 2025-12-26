# Navigation App

A Flutter application that includes a service for controlling the Roland V-160HD video mixer.

## Roland V-160HD Service

A Dart library for controlling the Roland V-160HD video mixer via TCP socket commands.

### Features

- Full support for VIDEO, AUDIO, METER, CONTROL, SYSTEM, CAMERA, PinP, DSK, SPLIT, SEQUENCER, and GRAPHICS commands.
- Asynchronous command sending with ACK waiting.
- Response parsing for all query commands.
- Input validation and error handling.
- SSL support for secure connections.

### Usage

```dart
import 'package:navigation_app/services/roland_service.dart';

final service = RolandService(host: '192.168.1.100', useSSL: true);
await service.connect();

// Set program to INPUT1
await service.setProgram('INPUT1');

// Get fader level
await service.getFaderLevel();

// Listen for responses
service.responseStream.listen((response) {
  if (response is FaderLevelResponse) {
    print('Fader level: ${response.level}');
  }
});

// Disconnect
service.disconnect();
```

### Commands Supported

See the class documentation in `lib/services/roland_service.dart` for the full list of supported commands.

### Testing

Run tests with:

```bash
flutter test
```

### Troubleshooting

- **Connection Issues**: Ensure the device IP and port (default 8023) are correct. Check firewall settings.
- **Command Failures**: Verify parameter ranges and formats against the official documentation.
- **Response Parsing**: All query responses are parsed into response objects; unparsed responses are emitted as strings.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Prerequisites

You need to have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed and added to your PATH.
