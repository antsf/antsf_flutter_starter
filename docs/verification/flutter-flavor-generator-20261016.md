# Flutter flavor generator — local verification, 2026-10-16

## Scope and verdict

- Source: [approved specification](../specs/flutter-flavor-generator.md).
- Branch: `feat/flutter-flavor-generator`, base `c0e8c44`.
- CLI: `packages/antsf_flutter_starter_cli`; runtime router changes already in the
  checkout are separate WIP and were not modified by this continuation.
- **Local Dart/Flutter and Android gates pass. iOS build acceptance is open.**
- This records local verification before PR publication. Delivery/remote CI state
  must be read from the PR, not inferred from this checkpoint. No signing-secret
  setup, domain deployment or production release was performed.

## Fixes exercised

1. CLI `run`/`build` now await the Flutter launch inside their error boundary.
   A failing-process regression first reproduced an uncaught `ProcessException`,
   then passed with the sanitized CLI error and exit code 2.
2. Android Gradle scripts import `File` and `Properties`; qualified `java.*`
   expressions previously collided with Gradle's `java` extension and prevented
   compilation of an actual generated app. Real APK builds now pass.
3. Native Gradle failures retain the standalone guard's sanitized diagnostic.
   Direct Flutter commands now expose the specific conflicting selector/version
   or stale-configuration reason rather than only a generic guard error.
4. CocoaPods legitimately changes `Runner.xcodeproj/project.pbxproj`. Generated
   pre/post-integrate hooks now bracket that operation with the same recoverable
   journal as sync. A verified integration refreshes the managed Runner hash and
   native baseline, preserving CocoaPods references in subsequent rendering.
   Executed Dart regressions cover manual conflict refusal, post-install guard,
   next sync, interrupted installation/recovery, and rejection of other tracked
   edits during installation. **These are not an actual CocoaPods/Xcode build.**
5. New apps explicitly disable project-level Swift Package Manager integration
   to avoid a second independent native-project writer. The app keeps Flutter's
   default Cupertino icon-font dependency; a fresh release build no longer emits
   the missing-Cupertino-font warning. The obsolete build_runner flag was removed.
6. Independent pre-commit review reproduced a distribution blocker: Git ignored
   four hashed native baseline files. Creation now excludes nested ignore files,
   explicitly tracks the baseline, and generates precise `-text` attributes for
   guarded outputs/inputs. A new real creation → ordinary Git add → index checkout
   regression with `core.autocrlf=true` first failed for the four missing files,
   then passed with every hash preserved and the Android guard exiting 0.

## Executed checks

| Check | Result |
|---|---|
| CLI path activation and installed-command help/create | Pass, exit 0 |
| CLI `dart format --output=none --set-exit-if-changed lib bin test` | Pass |
| CLI `dart analyze --fatal-infos` | No issues |
| CLI full suite, including real fresh Android template and Git round-trip | 60 passed; no skips |
| Starter `flutter analyze --fatal-infos` / `flutter test` | No issues; 26 passed |
| Real two-flavor app: pub get, codegen, analyze, tests | No issues; 16 passed |
| Real three-flavor app: pub get, codegen, analyze, tests | No issues; 17 passed |
| Fresh final three-flavor app, including CocoaPods helper and SPM setting | No issues; 17 passed |
| Final fixture: sync, analyze, standalone iOS guard, tests | All commands exit 0 |
| Workflow actionlint 1.7.12 | Pass; ShellCheck integration disabled because not installed |
| `git diff --check` | Pass |

Full CLI suite command (run from its package directory):

```sh
ANTSF_ANDROID_TEMPLATE=<fresh-flutter-project-root> dart test
```

The environment variable must point at a fresh project's root containing
`android/app/build.gradle.kts`. Without it, the real-template compatibility test
is intentionally skipped; that is not the verification configuration used here.

### Packaged Android metadata

Built and inspected with Android SDK 36.1.0 `aapt dump badging`, not inferred from
Gradle source. The earlier three-flavor fixture is named `flavor_three`.

| APK | Application ID | Display name | versionName | versionCode |
|---|---|---|---|---|
| dev debug | `com.antsf.flavorthree.dev` | `[DEV] Flavor Three` | `1.0.4-b51` | `51` |
| stg debug | `com.antsf.flavorthree.stg` | `[STG] Flavor Three` | `1.0.0-b1` | `1` |
| prod debug | `com.antsf.flavorthree` | `Flavor Three` | `1.0.0` | `1` |

SHA-256 of those debug APKs at inspection time:

- dev: `1c5588ae71c6c63128c461a4611bc936ff715be7fa7797aeb4663e0e67b8e90b`
- stg: `d69e73816774c0ee0999b7f439f1d17617666a009564e66db70b8371d24537a4`
- prod: `8e07ab309606b6d985bd107c1482c8ea0220e9cb3913f4064d399ab21dc910cd`

The extracted launcher PNGs were visually inspected: green DEV badge, amber STG
badge, and an unbadged blue production icon. Widget tests exercise non-prod
banners and production's absence of a banner. There was no physical-device UI run.

`dev` release APKs also built successfully in the earlier fixture and the final
fresh `flavor_final` fixture. Non-prod release signing is a development artifact,
not a store-signing claim. Transitive Java source/target-8 deprecation warnings
remain; they did not fail the builds. Production release without external signing
was deliberately rejected.

### Negative direct-build and synchronization checks

The following used real direct Flutter commands, not only wrapper validation:

- Missing flavor and unknown flavor: refused, exit 1.
- `--flavor dev --dart-define=APP_ENV=prod`: refused, exit 1, selector diagnostic.
- Conflicting `--build-name=9.9.9` or `--build-number=999`: refused, exit 1.
- Edited configuration without synchronization: refused, exit 1.
- Prod release without signing: refused, exit 1; no debug-key fallback.

On a real default two-flavor app, the verification harness changed only
`dev/android` to `3.2.1+73`, compared the complete decoded configuration against a
single-target expected change, and found no unrelated changes. Repeated sync
produced identical managed hashes and preserved every captured handwritten Dart
file. A managed-file conflict caused exit 2 before any other managed file changed.
Recovery and interrupted-operation paths also run in the CLI suite.

## Acceptance map

| IDs | Status and evidence |
|---|---|
| A01 | Pass: CLI validation, destination refusal, transport, unknown-flavor and failure-propagation tests |
| A02 | Pass: installed local CLI created real two-/three-flavor apps; Git installation documented |
| A03 | Pass: actual dependency resolution, router/Riverpod codegen, analyze and tests on generated apps |
| A04 | Pass: real dev/stg/prod APKs; metadata inspected from each package |
| A05 | Pass: packaged independent dev Android version; differing dev iOS config; real single-target update comparison |
| A06 | Pass: direct builds refuse missing/unknown flavor, stale config, selector contradictions and version overrides |
| A07 | Pass: URL/HTTP policy and logging-redaction tests, including actual local HTTP requests; production logging remains off |
| A08 | Pass locally: Android/iOS icon renderer tests and custom overrides, extracted Android icons and banner widget tests; dev release compiles; no device visual claim |
| A09 | Pass: real repeated sync, target isolation/handwritten preservation/conflict checks and failed-write/recovery tests; CocoaPods boundary exercised by Dart subprocesses |
| A10 | Pass for configuration/templates: per-flavor native links, host/path allowlist, disabled-link behavior; live domain/certificate verification pending as required |
| A11 | Pass: real prod release refuses missing signing; no debug-key fallback or generated signing secrets |
| A12 | CI preparation done and actionlint passes; **actual macOS execution remains open** |
| A13 | Met: iOS consistently reported configuration-checked / build unverified |
| A14 | Pass: 26 starter tests and analyzer; unrelated router/test WIP untouched; CLI dependencies isolated |

## iOS gate and CI readiness

`.github/workflows/flavor-generator.yml` has a macOS dev/stg/prod matrix. Each job
now installs CocoaPods, checks guards, syncs, reinstalls CocoaPods, checks guards
again, builds an unsigned simulator app, and verifies its packaged bundle ID,
display name, version `2.3.4`, and build `7`. Actual macOS execution may still
expose SDK/CocoaPods/Xcode integration issues; YAML validation cannot close A12.

Per the Android-first delivery decision, ordinary PR/main CI runs CLI checks and
actual Android builds/metadata checks. The deferred iOS matrix is opt-in through
`workflow_dispatch` with `verify_ios: true`, not a PR/main acceptance gate.

The current machine is Windows and has neither Xcode nor CocoaPods. No remote
workflow was started during local validation. Commit/push/PR were subsequently
authorized; see the PR for current delivery and Android CI status. Production provisioning/signing and
actual universal/app-link verification also remain application-owner work.

## Local evidence locations

All generated fixtures/logs are outside the source checkout under
`C:/Users/atgpg/AppData/Local/hermes/cache/scratch/`:

- `antsf_two_20261016/`: default two-flavor fixture.
- `antsf_three_20261016/`: three-flavor fixture and the inspected debug APKs.
- `antsf_final_20261016/`: fresh final template and successful dev release APK.
- `antsf_evidence_20261016/results.json`: inspected artifact metadata/hashes and
  negative-build/sync assertions; adjacent logs and `apk-icons.png`.
- `verify_antsf_flavors.py`: executed local artifact/safety verification harness.

Scratch files are ephemeral. This report and the committed-in-future test source,
not the continued existence of scratch paths, are the durable handoff.
