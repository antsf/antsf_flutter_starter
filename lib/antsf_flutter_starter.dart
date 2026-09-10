/// antsf_flutter_starter — opinionated app-starter building blocks that
/// deliberately sit ABOVE `flutter_corekit` rather than inside it:
/// navigation (auth/onboarding route guards for go_router) and Riverpod
/// wiring helpers. See package description / README for the rationale
/// (`flutter_corekit` stays a state-management-agnostic toolkit; this
/// package is where the "how we build an app" opinions live).
library;

export 'src/router/route_guard.dart';
export 'src/router/router_error_screen.dart';
export 'src/router/router_listenable.dart';
