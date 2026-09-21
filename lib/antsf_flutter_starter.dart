/// antsf_flutter_starter — opinionated app-starter building blocks that
/// deliberately sit ABOVE `flutter_corekit` rather than inside it:
/// navigation (auth/onboarding route guards for go_router) and Riverpod
/// wiring helpers. See package description / README for the rationale
/// (`flutter_corekit` stays a state-management-agnostic toolkit; this
/// package is where the "how we build an app" opinions live).
library;

export 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:go_router/go_router.dart';
// riverpod_annotation re-exports a handful of code-generator-only symbols
// (dollar-sign-prefixed, plus ProviderElement) that riverpod_generator's
// generated code consumes internally -- they aren't meant to be part of a
// public API, so flutter analyze flags re-exporting them here
// (invalid_export_of_internal_element). Hidden explicitly rather than
// switching to a narrow show list, so new *public* symbols added upstream
// still flow through automatically.
export 'package:riverpod_annotation/riverpod_annotation.dart'
    hide
        ProviderElement,
        $AsyncClassModifier,
        $AsyncNotifierProviderElement,
        $ClassFamilyOverride,
        $ClassProvider,
        $ClassProviderElement,
        $Family,
        $FamilyOverride,
        $FunctionalFamilyOverride,
        $FunctionalProvider,
        $FutureModifier,
        $FutureProvider,
        $FutureProviderElement,
        $LazyProxyListenable,
        $NotifierProviderElement,
        $Observable,
        $Provider,
        $ProviderElement,
        $ProviderPointer,
        $Ref,
        $RefArg,
        $Result,
        $StreamNotifierProviderElement,
        $StreamProvider,
        $StreamProviderElement,
        $SyncValueProvider;

export 'src/router/route_guard.dart';
export 'src/router/router_error_screen.dart';
export 'src/router/router_listenable.dart';
