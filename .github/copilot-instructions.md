# GitHub Copilot Instructions for Navigation App

## ⚠️ MANDATORY REQUIREMENTS ⚠️
**Before completing ANY task, you MUST:**
1. Run `flutter analyze` and fix ALL errors and warnings
2. Run `flutter test` and fix ALL test failures
3. Verify both commands complete with zero issues

**No task is complete until both commands pass successfully.**

---

## Project Overview
This is a Flutter application for controlling Roland V-160HD video switchers and Panasonic PTZ cameras. The app provides a unified control interface for video production workflows.

## Architecture

### Core Services
- **RolandService** (`lib/services/roland_service.dart`): Handles TCP socket communication with Roland V-160HD switchers
- **PanasonicService** (`lib/services/panasonic_service.dart`): Manages HTTP-based communication with Panasonic cameras

### State Management
- Uses StatefulWidget with setState for UI updates
- Multi-camera configuration stored in `PanasonicCameraConfig` objects
- Single Roland connection with multiple Panasonic camera connections supported

### Key Components
- **RolandControlPage**: Main UI with 3 tabs (Basic, PinP, Panasonic)
- **PanasonicCameraConfig**: Configuration class for managing individual camera instances

## Code Style & Patterns

### Flutter Conventions
- Use Material 3 design system
- Prefer `const` constructors wherever possible
- Use nullable types appropriately (`?` suffix)
- Follow Dart naming conventions (camelCase for variables, PascalCase for classes)

### Service Layer
- Services use async/await for network operations
- TCP connections (Roland) use socket streams
- HTTP requests (Panasonic) use standard HTTP client
- Always handle errors with try-catch blocks

### State Updates
- Always wrap state changes in `setState(() { ... })`
- Dispose controllers and services in `dispose()` method
- Initialize state in `initState()` method

## Common Patterns

### Adding New Camera Functions
```dart
Future<void> _newCameraFunction() async {
  if (_panasonicService == null) return;
  try {
    final response = await _panasonicService!.functionName();
    setState(() => _panasonicResponse = 'Result: $response');
  } catch (e) {
    setState(() => _panasonicResponse = 'Error: ${e.toString()}');
  }
}
```

### Adding Roland Commands
```dart
void _newRolandCommand() => _rolandService?.commandName(parameters);
```

### Multi-Camera Operations
- Always use `_selectedCameraIndex` to reference the current camera
- Check connection status before operations: `if (_panasonicConnected) { ... }`
- Use getter `_panasonicService` to access the selected camera's service

## Testing & Quality

### ⚠️ MANDATORY: Before Completing Any Task
**CRITICAL**: You MUST run both `flutter analyze` AND `flutter test` and fix ALL errors before considering work complete.

**Required Steps (NO EXCEPTIONS):**
1. Make your code changes
2. Run `flutter analyze`
3. Fix ALL errors and warnings (if any)
4. Re-run `flutter analyze` until it shows "No issues found!"
5. Run `flutter test`
6. Fix ALL test failures and errors (if any)
7. Re-run `flutter test` until all tests pass
8. **Only then is the task complete**

**Exit Codes to Check:**
- `flutter analyze` must exit with code 0
- `flutter test` must exit with code 0
- Any non-zero exit code means there are issues that MUST be fixed

### Common Analyzer Issues
- Missing `@override` annotations
- Unused imports or variables
- Missing `const` constructors
- Non-final fields that should be final
- Duplicate method definitions

## Network Configuration
- Roland V-160HD default: `10.0.1.20:8023`
- Panasonic cameras default range: `10.0.1.10-12`
- All network operations should handle connection failures gracefully

## UI Guidelines
- Use `ElevatedButton` for primary actions
- Use `FilledButton` for connect/disconnect actions
- Show loading indicators during async operations
- Display connection status with colored indicators
- Provide clear error messages in colored containers

## File Organization
```
lib/
  main.dart                 # Main app and UI
  services/
    roland_service.dart     # Roland V-160HD control
    panasonic_service.dart  # Panasonic camera control
    documentation/          # API documentation
```

## Important Notes
- Roland service uses TCP sockets - keep connection alive
- Panasonic service uses stateless HTTP requests
- Support for multiple simultaneous camera connections
- Single Roland connection at a time
- Always validate user input (IP addresses, preset numbers, etc.)

## Dependencies
Check `pubspec.yaml` for current dependencies. When adding new packages:
1. Add to `pubspec.yaml`
2. Run `flutter pub get`
3. Import in relevant files
4. Update this documentation

---

**Remember**: Run `flutter analyze` and `flutter test` after every change and fix all issues before submitting work.
