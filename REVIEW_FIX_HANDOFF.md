# Archived: starter review fixes — checkpoint 2026-10-01

> **Historical archive, recorded 2026-10-16.** The checkpoint below describes
> the local state and permissions on 2026-10-01; it is not the current delivery
> status, installation guidance, or authorization policy.
>
> Its runtime fixes are included in released **v0.2.1**, together with CLI 0.1.0.
> [PR #6](https://github.com/antsf/antsf_flutter_starter/pull/6) was merged as
> `68f9db02bd714f000f02b842e17d615444bcf1e8`; the immutable
> [release tag](https://github.com/antsf/antsf_flutter_starter/releases/tag/v0.2.1)
> points to that commit. Current instructions: [README](README.md),
> [release notes](RELEASE_NOTES.md), and
> [CLI README](packages/antsf_flutter_starter_cli/README.md).
> Historical workstation paths, local overrides, unpublished-state statements,
> and scratch evidence below are preserved for context, not recommendations.
> This archive/formatting follow-up does not change package behavior or retag
> the release.

## Scope/specs and actual implementation

Priority now corekit → starter; notifications/save_to_dir deferred by user. Minimal risk-based new tests, reuse existing suites. No commit/push/PR/publish, worktree/clone, global SDK/config or protected-file change.

- Branch: `fix/independent-review-20260930`
- Baseline/current HEAD: `8b909a3c4255d89ffda4790fa271be1ec61a7527`
- Original dirty `example/pubspec.lock` and previously approved SDK constraint edits retained. Baseline hashes/files/diffs saved before these source edits.
- SDK: Flutter 3.47.1 / Dart 3.13.1. Package/example `^3.13.1` downgrade was explicitly approved by user; no SDK installed or replaced.

Specs/plan executed: restore generated-part symbols through the single barrel; preserve public routes while auth is loading/error without opening protected routes; make provider router ownership explicit; regenerate example; run existing gates and one integration smoke; independent read-only review.

## Fixes

1. Full `riverpod_annotation` re-export (narrow lint ignore with rationale), rather than hiding symbols consumed by generated parts. Example provider and AsyncNotifier libraries now import only the starter barrel for the stack. Actual Riverpod and GoRouter generation succeeds; analyzer and smoke test compile/use those generated parts.
2. `AuthRouteGate` respects `publicRoutes` during loading/error. Protected routes still redirect to splash/login. Authenticated/auth-only overlap retains existing home redirect, explicitly documented.
3. Example stores `GoRouter` and registers `ref.onDispose(router.dispose)`. Helper/README snippets show ownership too. Smoke test verifies disposal; no claim of a pre-fix persistent memory leak.
4. README/example docs now give real codegen/test commands and local dependency setup, removing old unverified APK-success and stale test-count claims.

## Executed gates (native Windows tools, all final exit 0)

| CWD | Command | Actual result |
|---|---|---|
| package | `flutter pub get` | 0, sibling patched corekit via override |
| example | `flutter pub get` | 0, sibling patched corekit via override |
| example | `dart run build_runner build` | 0, actual provider/notifier/typed-route outputs generated |
| package | `dart format lib test example/lib example/test` | 0; mechanical formatting on some otherwise untouched files |
| package | `flutter analyze --no-pub` | 0, No issues |
| package | `flutter test --no-pub --reporter expanded` | 0, **26 passed** |
| example | `flutter analyze --no-pub` | 0, No issues |
| example | `flutter test --no-pub --reporter expanded` | 0, **1 passed**, startup/login/logout + router disposal |
| package | `git diff --check` | 0 |

Two initial informational lint failures in the new smoke test (relative lib imports) were corrected to `package:example/...`; final analyzer is clean. The first codegen invocation's removed `--delete-conflicting-outputs` flag was ignored by installed build_runner; docs corrected and real plain `build` rerun exit 0. These are harness/docs corrections, not upstream application defects.

## Local use / delivery boundary

This is an uncommitted/unpublished diff. Declared corekit Git dependency remains unchanged; blindly consuming remote `main` does NOT consume these patches. Root/example `pubspec_overrides.yaml` resolve sibling corekit only for local paired-checkout validation. New app can use:

```yaml
dependencies:
  antsf_flutter_starter:
    path: C:/src/flutter_dir/my_packages/antsf_flutter_starter
dependency_overrides:
  flutter_corekit:
    path: C:/src/flutter_dir/my_packages/flutter_corekit
```

Adjust paths. Keep build_runner/riverpod_generator/go_router_builder in consuming app dev dependencies. No global override or environment change. Do not inadvertently publish/commit workstation-specific override policy without deciding distribution strategy.

**Fixed + unit/codegen/example verified. Independent final source review PASSED with no findings** (`independent-final-review.json`). Review inspected the actual diff/generated parts and existing successful gate logs; it did not rerun Flutter or create extra tests. No Android/iOS device launch or platform-plugin verification is claimed; widget/VM smoke is not native device proof. Neither notifications nor save_to_dir is approved by this checkpoint. User's delivery target is GitHub dependencies for OMS/PH app; local overrides are validation-only. Commit/push/PR still require explicit approval under the original safety boundary before these patches are remotely consumable.

## Evidence

`C:/Users/atgpg/AppData/Local/hermes/cache/scratch/flutter-packages-fixes-20261001/starter/` contains baseline snapshot, `commands.jsonl`, full per-command logs, and final review JSON (when delivered). Scratch is pruneable; this handoff preserves the durable actionable status. Baseline original four-repo snapshots remain under `flutter-packages-fixes-20260930` and reports under `C:/src/reviews/flutter-packages-20260930/`.
