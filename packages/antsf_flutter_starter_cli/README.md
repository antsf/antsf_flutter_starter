# antsf Flutter Starter CLI

A separate Dart tool for creating new Android/iOS apps with native `dev`/`prod`
flavors and optional `stg`. It is not a dependency of the runtime starter package.
Approved requirements: [flavor generator specification](../../docs/specs/flutter-flavor-generator.md).

## Prerequisites

- Flutter 3.47.1 / Dart 3.13.1 is the initial tested toolchain.
- A bootstrapped Flutter SDK on PATH (`flutter --version` must work).
- Android SDK/JDK for Android builds; Xcode/macOS for iOS builds.
- Git/network access to the pinned starter/corekit dependencies.

The CLI invokes the installed Flutter tools snapshot through its Dart executable,
using structured subprocess arguments rather than interpolating names into a
shell command. Missing prerequisites and failed subprocesses are errors, not a
successful partial project.

## Install from this checkout

From the repository root:

```sh
dart pub global activate --source path packages/antsf_flutter_starter_cli
dart pub global run antsf_flutter_starter_cli:antsf_starter --help
```

Add your Pub cache `bin` directory to PATH to use the shorter `antsf_starter`
command. Alternatively, run `dart run bin/antsf_starter.dart` from this package.
No global activation is required for development/tests.

### Install from Git

The generator is included in source release `v0.2.1` (runtime 0.2.1, CLI 0.1.0).
Older starter releases do not contain this package. Install the release tag
rather than following a mutable feature branch:

```sh
dart pub global activate --source git https://github.com/antsf/antsf_flutter_starter.git --git-path packages/antsf_flutter_starter_cli --git-ref v0.2.1
```

This is a Git source installation, not a pub.dev publication. For immutable
automation, pin the full commit resolved by `v0.2.1`. See [CLI changelog](CHANGELOG.md) and
[repository release notes](../../RELEASE_NOTES.md) for scope and limits.

## Create an application

```sh
antsf_starter create ../sample_app --name sample_app --org com.antsf --display-name 'Sample' --dev-api https://dev.example.net --prod-api https://api.example.net
```

The `example.net` URLs above are test/documentation inputs, not live backends.
Supply your actual URLs for an application. Generation/build does not require a
successful response from a backend and does not assert that a URL is reachable.

Add staging by supplying `--stg-api https://stg.example.net`. Default native IDs
are derived from organization and project name (underscores removed for bundle-ID
compatibility), with `.dev` / `.stg` added to the non-production variants.
Non-production names, launcher icons, and in-app banners retain their labels in
release build mode. Prod receives no environment banner.

Options:

- `--icon path/to/base.png`: base production image; derive labeled dev/stg images.
- `--dev-icon`, `--stg-icon`, `--prod-icon`: override the image for a flavor.
- No icon supplied: use a clearly documented placeholder and replace it later.
- `--allow-dev-http`: opt into HTTP for local dev hosts/addresses only; stg/prod
  remain HTTPS-only. Public DNS names that resemble private IPs are not local.
- `--dev-link-host`, `--stg-link-host`, `--prod-link-host`: enable optional verified
  HTTPS link configuration for the selected flavor(s).
- `--link-path /open`: allowed path prefix; repeat for multiple prefixes.
- `--starter-path /absolute/path/to/antsf_flutter_starter`: local runtime checkout
  for development. Default runtime dependency uses a full reviewed Git commit.
- `--no-setup`: explicitly skip dependency resolution/code generation. Such output
  still requires the documented setup commands before it can run.

Required values and image sources are validated before publishing the destination.
A non-empty destination is refused. Creation is staged on the same filesystem;
failed creation/setup does not publish a partially generated app or remove files
that already existed in the requested destination. This is not a migration tool.

## Configure and synchronize

`antsf_flavors.json` is the versioned source of truth. It contains only non-secret
configuration: project identity, flavor settings, per-platform versions, API/logging
policy, optional icon sources, and optional link settings. Unknown fields and
missing required values are rejected instead of silently defaulted.

```sh
antsf_starter validate --project ../sample_app
antsf_starter sync --project ../sample_app
antsf_starter version --project ../sample_app --flavor dev --platform android --name 1.0.4 --build 51
antsf_starter version --project ../sample_app --flavor stg --platform ios --name 2.0.3 --build 88
```

Version editing is explicit and addresses exactly `(flavor, platform)`. It never
increments another counter or modifies another platform's version. Dev Android
`1.0.4` + `51` becomes `1.0.4-b51`; iOS has its own numeric marketing/build fields.
Ordinary builds do not change the counters.

Managed output includes `lib/core/config/`, native flavor settings, generated
icons, link templates/docs, `.gitattributes`, and `tool/flavor_guard.dart`. Scaffold features,
router, DI, theme, main, tests, and pubspec dependencies become application-owned
at creation and are not overwritten by subsequent flavor synchronization.

`.antsf/native-base` preserves the original Flutter native templates so rendering
is deterministic rather than repeatedly patching already-patched projects.
`.antsf/managed.json` records source/output hashes. Keep these in version control;
do not hand-edit them. Do not commit `.antsf/sync.lock` or transaction journals.

All conflicts are checked before writes. Manual changes in a managed file stop
sync with the path and remediation instructions. Preserve your edits elsewhere
and restore the generated baseline before retrying; there is no silent force
regeneration of the whole application. Source icons are inputs, not overwritten
outputs, and replacing them requires sync.

Synchronization is journaled and serialized. A process interruption leaves a
marker that blocks builds until recovery:

```sh
antsf_starter recover --project ../sample_app
```

Recovery restores the pre-transaction snapshots; inspect them, then retry sync.
Do not delete a transaction marker just to bypass a failed build.

## Run/build explicitly

```sh
antsf_starter run --project ../sample_app --flavor dev
antsf_starter build --project ../sample_app --flavor dev --platform android --mode debug
antsf_starter build --project ../sample_app --flavor prod --platform android --mode release
antsf_starter build --project ../sample_app --flavor stg --platform ios --mode debug --simulator --no-codesign
```

Native build guards also protect direct `flutter run/build --flavor ...` commands.
Missing/unknown flavor, stale config/output/source assets, an interrupted sync,
or a contradictory Dart environment selector is an error. Native flavor chooses
the runtime configuration; there is no fallback to production.

Do not use Flutter `--build-name` / `--build-number` overrides. The wrapper does not
accept them; edit target versions in configuration instead. Flutter always passes
pubspec values to native build tools, so the generated pubspec uses the sentinel
`0.0.0+1`. Native guards accept that baseline or the exact target version and reject
other values. A direct override equal to the baseline cannot be distinguished from
Flutter's ordinary forwarding, but it still cannot override native flavor metadata.
Packaged versions are always taken from the per-flavor/per-platform configuration.

Production release signing must be configured externally. Follow the generated
native signing integration comments; never track keystores, certificates, signing
passwords, or provisioning profiles in configuration. Prod debug APKs and unsigned
iOS simulator builds are validation artifacts, not distributable store releases.

### CocoaPods ownership and recovery

Generated apps use CocoaPods, with Flutter's project-level Swift Package Manager
integration disabled. Do not enable an independent native-project writer without
revisiting the managed-file contract. The generated Podfile's `pre_integrate` hook
validates current managed outputs before CocoaPods changes the Runner project.
Its `post_integrate` hook validates that other tracked inputs/outputs are unchanged,
records the integrated Runner project as the next native rendering baseline, and
refreshes its hashes. Standard CocoaPods framework references and `[CP]` phases
then survive future flavor synchronization. Manual edits before installation are
still conflicts, not silently adopted changes.

An interrupted installation leaves the normal synchronization recovery journal;
builds and sync stop until `antsf_starter recover` restores the prior Runner project,
native baseline, and manifest. Restore unrelated manual changes separately and
retry `pod install`. Do not edit generated files while CocoaPods integration runs.
On upgrading an already-generated app, the pubspec remains application-owned:
add `flutter.config.enable-swift-package-manager: false` explicitly before using
the CocoaPods-only workflow.

## Optional links and logging

Link/API hosts are independent. `docs/flavor-links.md` in the generated app lists
missing certificate fingerprints/Apple Team IDs and manual server deployment
steps. Templates remain explicitly incomplete when evidence is missing. Native
configuration alone is not proof of domain verification.

Network clients use corekit with its default verbose logger disabled. Non-production
metadata logging must exclude credentials, cookies, body data, and sensitive URL
query/path values. Production debug/network logging is off. Firebase and production
crash reporting remain optional application-level choices.

## Development and evidence

```sh
dart pub get
dart analyze
dart test
```

Exercise real generated two- and three-flavor apps as well as the CLI tests. The
repository workflow generates a real three-flavor app and builds/inspects all
Android flavors on PRs and main. iOS is deferred: its macOS matrix runs only through
`workflow_dispatch` with `verify_ios: true`. iOS stays **build unverified** until that workflow
execution succeeds; writing its YAML is not a successful iOS build. No publish or
release-deploy job is enabled by this workflow.

The macOS job also runs CocoaPods, guards, sync, and a second installation before
building, then inspects the packaged identifier, display name and independent iOS
versions. Local evidence and remaining limits are recorded in
[the verification report](../../docs/verification/flutter-flavor-generator-20261016.md).

All files hashed by the guard must survive normal Git check-in. Native baseline
copies deliberately omit nested `.gitignore` files; narrow root exceptions keep
the baseline tracked. Generated `.gitattributes` preserves exact guarded bytes
even with `core.autocrlf=true`; application-owned files retain normal Git policy.
The CLI suite tests real creation, ordinary `git add`, index checkout, byte hashes,
and the guard after checkout. Do not force-add missing inputs as a workaround.
