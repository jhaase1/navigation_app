# Codebase Critique Prompt

Use this prompt to get an AI-generated critique of the navigation_app codebase.

**Prompt:**

```
You are an expert Flutter developer with extensive experience in Dart, mobile app development, and video production equipment control. Analyze the provided Flutter codebase for an application that controls Roland V-160HD video switchers and Panasonic PTZ cameras.

The codebase includes:
- Main app in lib/main.dart
- Services for Roland (TCP socket) and Panasonic (HTTP) communication
- Models for camera configurations
- Widgets for UI tabs (Basic, PinP, Panasonic)
- Tests for services

Provide a detailed critique covering the following aspects:

1. **Code Quality and Style**
   - Adherence to Dart/Flutter conventions
   - Code readability and maintainability
   - Use of const constructors, nullable types, etc.

2. **Architecture and Design**
   - Separation of concerns (services, models, widgets)
   - State management approach
   - Multi-camera support implementation

3. **Functionality and Features**
   - Completeness of Roland and Panasonic control features
   - Error handling and user feedback
   - Network communication robustness

4. **Testing**
   - Test coverage and quality
   - Mock implementations
   - Integration testing

5. **Documentation**
   - Code comments
   - README and other docs
   - API documentation for services

6. **Performance and Efficiency**
   - Network operations
   - UI responsiveness
   - Resource management (dispose, etc.)

7. **Security**
   - Network security (TCP/HTTP)
   - Input validation
   - Sensitive data handling

8. **Dependencies and Packages**
   - Appropriateness of pubspec.yaml dependencies
   - Version management

9. **Platform and Build**
   - Android/iOS/Web support
   - Build configuration

10. **Best Practices**
    - Flutter-specific patterns
    - Async/await usage
    - Error handling patterns

For each section, provide:
- Strengths observed
- Weaknesses or areas for improvement
- Specific code examples (with file paths and line numbers if possible)
- Actionable recommendations

Conclude with overall assessment and priority recommendations.
```