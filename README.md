# omni_ai

A new Flutter project.

## Kinopoisk metadata

Online title search uses the Kinopoisk API key supplied through
`KINOPOISK_API_KEY`. The local demo catalog remains available without a key.

```powershell
flutter run --dart-define=KINOPOISK_API_KEY=your-api-key
flutter build apk --debug --dart-define=KINOPOISK_API_KEY=your-api-key
```

The key is embedded in the app binary. Use a restricted key and avoid
committing it to source control.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
