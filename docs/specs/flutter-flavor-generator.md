# Flutter Flavor Standard and Project Generator

Status: requirements approved through the grilling session; implementation pending.
Scope of this document: the reusable standard, generator behavior, safety contracts,
and acceptance evidence. Writing this specification does not mean the generator,
Android builds, or iOS CI have been implemented or verified.

## 1. Objective

Provide a repeatable starting point for new Flutter mobile applications with native
Android and iOS flavors. Deliver both a documented standard in
`antsf_flutter_starter` and an installable Dart CLI package in the same repository.
The CLI creates applications; the existing Flutter package remains a reusable
runtime library, not a container for generator-only dependencies.

Default flavors are `dev` and `prod`. `stg` is selectable during creation.
Configuration must not assume there can only ever be two flavors.

## 2. Approved decisions

| ID | Requirement |
| --- | --- |
| F01 | Generate new Android + iOS applications; do not migrate existing apps. |
| F02 | Reject non-empty destinations without overwriting their contents. |
| F03 | Use Flutter, `flutter_corekit`, `antsf_flutter_starter`, Riverpod, routing, theming, MVVM folders, and a runnable initial page. Do not generate a fake login flow. |
| F04 | Generate `dev` + `prod` by default; optionally generate `stg`. |
| F05 | Give each flavor a distinct native identity so installed applications and their default application data are separate. |
| F06 | Give non-production flavors distinct launcher icons, display names, and an in-app banner in debug, profile, and release modes. |
| F07 | Keep non-secret configuration centralized and synchronize Android, iOS, and Dart from it. |
| F08 | Maintain independent versions/build numbers for every flavor AND platform. Ordinary builds never increment them. |
| F09 | Require explicit flavor selection. Missing, unknown, stale, or contradictory configuration fails clearly; never fall back to prod. |
| F10 | Validate API URLs, transport policy, and logging policy for every generated flavor. |
| F11 | Offer optional Android App Links + iOS Universal Links, an example route, and server-association templates. Do not deploy server files. |
| F12 | Synchronize only generator-managed files/areas and stop on conflicting manual changes. |
| F13 | Provide signing integration points and documentation, without handling credentials or silently debug-signing production releases. |
| F14 | Verify the real generator output, not just the generator/package source. Include repeatable Android verification and an iOS simulator CI workflow on macOS. |

## 3. Product boundaries

### Included

- A separate, installable Dart CLI package within this repository.
- Initial local-checkout installation and documentation for installation from Git.
- Project creation inputs: destination/project name, organization/base application
  identity, application display name, enabled flavors, per-flavor API URLs, and
  optional icons/link settings.
- A documented, versioned configuration schema and a validation command.
- Explicit configuration synchronization and version-edit operations.
- Standard documentation and a representative example of the flavor pattern.
- Generated-project instructions for run, build, configuration changes, icons,
  optional links, signing, and verification.

### Excluded

- Adapting/migrating existing applications.
- Automatic release publication, repository creation, commits, pushes, or remote CI
  execution without separate authorization.
- Automatic backend deployment, association-file deployment, or credential storage.
- Mandatory Firebase or any other product-specific service.
- Full authentication/business features, web, and desktop application generation.
- Automatic version increments on build.

## 4. Runtime and package architecture

The CLI must remain separate from the Flutter runtime dependency graph. Image
processing, template rendering, configuration serialization, and native-project
editing belong to tooling, not to every consuming application.

Generated applications use:

- `flutter_corekit` for existing network, storage, theme, and error primitives;
  inspect its actual APIs before wiring them. Do not invent or duplicate services.
- `antsf_flutter_starter` for existing routing/state-management integration.
- Riverpod providers for dependency injection and view-model state.
- Typed routing consistent with the starter, with a real code-generation step if
  the selected pattern requires generated code.
- MVVM-oriented folders: `lib/core/{config,di,router,theme}/` and
  `lib/features/<feature>/{models,repository,viewmodels,views,widgets}/` as needed.
  Do not fill unused folders with fake domain implementations.
- One runnable initial screen, with no pretend authenticated session or login API.

Generated dependency declarations must be compatible with the actual package
exports and reviewed dependency versions. Git dependencies must resolve to
reproducible reviewed refs, not silently track a moving development branch. Tests
must exercise the exact resolved dependency and code-generation combination.

## 5. Flavor identities and visual policy

| Flavor | Android application ID / iOS bundle ID | Display name | Icon | In-app banner |
| --- | --- | --- | --- | --- |
| `prod` | Base identity | Base display name | Base production icon | None |
| `dev` | Base identity + `.dev` | `[DEV] <display name>` | Distinct color + `DEV` label | `DEV` |
| `stg` (optional) | Base identity + `.stg` | `[STG] <display name>` | Distinct color + `STG` label | `STG` |

Android uses the `app` flavor dimension. iOS uses shared flavor schemes and
matching build configurations. Do not confuse Flutter build mode with flavor:
`dev --release` is still dev and must retain all dev identity markers.

A single supplied production image is enough to derive non-production variants.
Allow per-flavor icon overrides. If no image is supplied, generate with a clearly
documented placeholder icon and support replacing it later. Validate image inputs
before mutation and generate the platform-required sizes/metadata. Production
must not receive a non-production label or banner.

The in-app banner must remain visible without obscuring important controls or
making the initial app unusable. Test it in release behavior as well as debug.

## 6. Central configuration and authority

Use one versioned, non-secret project configuration as the source of truth. Its
logical schema must represent:

- Project identity and base display name.
- The enabled flavor set and each flavor's native identity/display settings.
- API base URL and transport policy per flavor.
- Logging policy per flavor.
- Per-platform version data inside EACH flavor: Android `versionName` and
  `versionCode`, iOS marketing version and build number.
- Android version-name suffix policy, including the approved dev `-b<versionCode>`
  pattern.
- Base icon and optional flavor overrides.
- Optional link host/path settings and association-file prerequisites.
- Schema/generator compatibility information and synchronization state.

The concrete serialization format, filenames, and CLI command names are
implementation details to document before exposing them. They must not create
additional competing sources of truth.

Configuration, generated Dart constants, Android build settings, iOS build
settings, and any required build-time arguments must agree. Native flavor is the
authoritative environment selector; a separately supplied Dart environment value
cannot redirect a dev binary to prod configuration. Detect stale generated output
before producing a runnable/distributable artifact, not only after a successful
build.

Reject unknown flavors, duplicate native identities, missing required values,
invalid version values, invalid URLs, incompatible schema versions, and conflicting
build overrides with actionable diagnostics. No credentials, server secrets,
keystore passwords, signing keys, or certificates belong in this file.

## 7. Independent versioning

The complete version address is `(flavor, platform)`. For example, changing
`(dev, android)` must leave `(dev, ios)`, `(prod, android)`, `(prod, ios)`, and all
staging values untouched.

Version changes are deliberate configuration edits or an explicit tooling command
that names the target flavor and platform. Synchronization renders those values;
it does not increment them. Repeating a build does not change configuration.

Android dev follows the user's pattern below. These literal values are reference
input from Trantara, NOT generator defaults and NOT API endpoint assumptions:

```kotlin
create("dev") {
    dimension = "app"
    resValue("string", "app_name", "[DEV] Trantara")
    applicationIdSuffix = ".dev"
    // Independent DEV version; do not inherit another flavor's counter.
    versionCode = 51
    versionName = "1.0.4"
    versionNameSuffix = "-b51"
    manifestPlaceholders += mapOf("hostName" to "jn-rorodev.prahu-hub.com")
}
```

Derive the dev suffix from its own configured Android build number so the two
cannot drift. iOS uses platform-valid marketing/build fields; do not copy an
Android suffix such as `-b51` into the iOS marketing version. Android and iOS may
have different versions and counters. Do not silently inherit `pubspec.yaml` or
another flavor's version when a required per-target value is absent.

If native/Flutter build flags override the authoritative version with a conflicting
value, reject the build rather than silently ship different metadata. Verify the
packaged Android version/application ID, not only the source configuration.

## 8. API transport, logging, and bootstrap safety

- Every enabled flavor requires a valid API base URL; placeholders and missing
  values must fail before application startup.
- `prod` and `stg` require HTTPS.
- Local HTTP is allowed for `dev` only through an explicit option. Generate only
  the platform/network exceptions necessary for the opted-in development use;
  do not weaken production transport policy.
- API hosts and App/Universal Link hosts are separate settings. Never infer one
  from the other or reuse the Trantara reference domain as a default.
- Dev/stg may log sanitized request/error metadata. Do not log authorization
  headers, cookies, passwords, tokens, request/response bodies, or sensitive URL
  query data by default. Sanitization must be exercised by tests.
- Prod has no debug/network logging enabled by this scaffold. This does not ban
  separately configured production crash reporting in a future application.
- Configuration failure is explicit and actionable, without exposing sensitive
  values. Never quietly choose another flavor or production endpoint.
- Do not require a live backend response just to generate/analyze/build the app;
  URL validation is not a fabricated health check.

## 9. Optional verified HTTPS links

When disabled, project generation does not require a domain or server association
configuration and must not enable broad catch-all link handling.

When enabled, generate:

1. Android intent filters using the configured host/path policy.
2. Matching iOS Associated Domains configuration for the selected flavor.
3. A typed example route and safe handling of unsupported links.
4. Templates/instructions for Android `assetlinks.json` and iOS
   `apple-app-site-association`, using the correct per-flavor application IDs.
5. A clear checklist of unresolved real-world requirements such as Android signing
   certificate fingerprints, Apple Team ID, entitlement/provisioning setup, and
   publishing association files on the domain.

Missing signing/team/domain evidence must remain explicitly incomplete. Do not
invent fingerprints, Team IDs, live server responses, or claim links are verified
because template files exist. Keep server deployment manual and document how
actual domain association is tested after deployment. Never automatically pass
an untrusted link to a privileged action.

## 10. Creation, synchronization, and failure behavior

### Creation

Validate inputs and tool prerequisites before modifying the destination. Reject
non-empty destinations and unsafe names/paths. Invoke subprocesses with structured
arguments rather than interpolating untrusted inputs into shell commands. Do not
silently initialize/commit/push a repository.

Produce a runnable app and complete setup instructions. Report failed subprocesses
honestly with the failing step and remediation; never present partial output as a
successful project. Avoid destructive rollback of paths not created by this run.

### Synchronization

Declare all generator-owned files/areas. Keep handwritten feature code outside
those boundaries. Track sufficient baseline information to distinguish a managed
output from a conflicting manual edit.

Before writing, validate the whole configuration and detect conflicts. On a
conflict, stop with exact affected paths and reconciliation instructions; do not
silently overwrite, discard, or partially synchronize the project. Repeating sync
without changes must be idempotent. An interrupted write must not leave silently
mixed flavor configurations.

Updates to versions, icons, or links must preserve unrelated flavor/platform data
and handwritten code. Do not regenerate the entire app to update one setting.

## 11. Signing and distribution boundaries

Provide documented integration points for Android keystores and iOS signing.
Actual credentials, profiles, and certificates are supplied outside this generator
by the application owner. Never add them to generated tracked configuration.

Production release output must not silently use debug signing. If required
production signing is missing, stop the distribution path with a clear message.
Document unsigned validation paths distinctly from distributable release builds.
An iOS simulator build without signing is test evidence, not an App Store artifact.

Dev/stg may use suitable development signing for test builds; release build mode
does not remove their non-production identities or visual markers.

## 12. Acceptance and evidence matrix

All rows below are implementation acceptance criteria, not claims of completed
execution. Keep real logs/artifact paths and pending-platform status in the
implementation report.

| ID | Required evidence |
| --- | --- |
| A01 | CLI tests cover valid/invalid inputs, destination refusal, unknown flavor, URL/transport validation, and failure propagation. |
| A02 | Create a real default dev/prod app and a real dev/stg/prod app with the actual CLI. Test local CLI installation and document Git installation. |
| A03 | Generated apps complete dependency resolution, required Riverpod/router code generation, `flutter analyze`, and `flutter test`. Analyze-only results are insufficient. |
| A04 | On Windows, produce real Android APKs for every enabled flavor in the three-flavor fixture. Inspect packaged identity/name/version metadata, not just Gradle text. |
| A05 | Tests plus real Android build evidence cover an independent dev version and differing Android/iOS configuration. Updating one `(flavor, platform)` leaves the others unchanged. |
| A06 | Verify missing/unknown flavor, stale configuration, contradictory Dart selector, and conflicting version override fail rather than choosing an environment silently. |
| A07 | Verify API URL/HTTP rules and logging redaction, including sensitive query/header values. Production debug/network logging remains off. |
| A08 | Check generated Android/iOS icon assets and banner widget behavior: dev/stg marked in release behavior, prod unmarked, custom icon overrides supported. Do not claim device visual QA without running it. |
| A09 | Sync tests cover idempotence, single-target edits, untouched feature files, conflict refusal before writes, and failed-write recovery. |
| A10 | Optional links have correct per-flavor host/path/native IDs and association templates; disabled links introduce no domain prerequisite. Mark live association verification pending until real server/signing checks occur. |
| A11 | Missing production signing does not fall back to debug-signed production release output. No signing secrets appear in generated tracked files. |
| A12 | Add macOS CI that generates the representative app, resolves/generates code, and performs unsigned iOS simulator builds for enabled flavors using the actual shared schemes. |
| A13 | Until that workflow actually succeeds, report iOS as configuration-checked / build unverified. Writing YAML or inspecting Xcode files is not successful iOS build evidence. |
| A14 | Existing starter tests remain valid; unrelated local router/test work is preserved. Generator dependencies do not leak into runtime consumers. |

Local acceptance requires real Android build evidence and the iOS CI path to be
prepared. An outstanding iOS execution must be explicitly visible; it is not a
waiver permitting a claim that both platforms have passed. Remote CI execution
requires separate authorization to push/run it.

## 13. Implementation sequence

1. Inspect actual starter/corekit exports, toolchain, code-generation constraints,
   and native flavor tooling; finalize concrete schema and command/file names.
2. Implement/test schema validation, independent version targeting, managed-output
   tracking, and CLI failure contracts before building complex rendering behavior.
3. Implement new-app creation and the minimal corekit/Riverpod/router/MVVM scaffold.
4. Add Android/iOS flavor mapping and explicit-selection/configuration guards.
5. Add icon variants, app banners, API/logging wiring, and optional links.
6. Add safe synchronization, signing integration documentation, and local/Git CLI
   installation instructions.
7. Generate real fixture apps, execute acceptance checks, inspect Android artifacts,
   and add the macOS iOS simulator workflow.
8. Report passed checks, artifact locations, and pending iOS/server/signing evidence
   separately. Do not commit, push, or publish without authorization.

## 14. Current delivery state

- The approved requirements are recorded in this document.
- CLI/runtime/native implementation has not started as part of the specification
  writing step.
- No Android/iOS build or generator test result is claimed by this document.
- Pre-existing local router/test changes and the handoff file remain out of scope.

Implementation evidence is tracked separately in
[the 2026-10-16 verification report](../verification/flutter-flavor-generator-20261016.md).
In particular, Windows/Android evidence does not close the macOS/iOS build gate.
