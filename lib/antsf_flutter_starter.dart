/// antsf_flutter_starter — opinionated app-starter building blocks that sit
/// ABOVE `flutter_corekit`'s network/storage/theme primitives, adding the
/// navigation (go_router auth/onboarding route guards) and state-management
/// (Riverpod wiring) opinions that `flutter_corekit` deliberately stays
/// agnostic about. See package description / README for the rationale.
///
/// Every package this library actually depends on — `flutter_corekit`,
/// `go_router`, `flutter_riverpod`, and `riverpod_annotation` — is
/// re-exported here, so a consuming app can set up a new project with a
/// single import (`package:antsf_flutter_starter/antsf_flutter_starter.dart`)
/// and get the full stack: network/storage/theme (via flutter_corekit) plus
/// routing and state management, without separately importing each one.
library;

export 'package:flutter_corekit/flutter_corekit.dart';
export 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:go_router/go_router.dart';
// Generated parts share their consumer's imports, so generator-support
// symbols must remain available through this single-import barrel. They are
// an intentional annotation bridge, not stable hand-written application APIs.
// ignore: invalid_export_of_internal_element
export 'package:riverpod_annotation/riverpod_annotation.dart';

export 'src/router/route_guard.dart';
export 'src/router/router_error_screen.dart';
export 'src/router/router_listenable.dart';
