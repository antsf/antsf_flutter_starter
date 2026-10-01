# Starter example

This app uses the starter barrel for Riverpod annotations/runtime and typed
GoRouter routes. `app_router.dart` and `auth_state.dart` do **not** directly
import `riverpod_annotation`: their generated parts validate single-import use.

From this directory, with Flutter 3.47.1 / Dart 3.13.1 (or compatible SDK):

```sh
flutter pub get
dart run build_runner build
flutter analyze --no-pub
flutter test --no-pub
flutter run
```

The example depends on this repository's starter source (`path: ../`), which
is standard for an in-repository example only. The starter itself resolves
corekit 3.1.1 from GitHub at commit
`8995c06884e7ac4ae004db3b357f6da5c642f96d`; no sibling-corekit override is used.
For a new OMS/PH app, use the GitHub starter dependency in `../README.md`,
not the example's local path dependency.

The smoke test exercises splash → login → home → logout and checks that
unmounting the provider scope disposes its router. This is a widget/VM check,
not proof that platform-specific corekit plugins work on a physical device.
See `../RELEASE_NOTES.md` for executed gates and release limits.
