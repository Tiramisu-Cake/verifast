# Validation matrix

**Full Linux make test PASS**: final tree687ae7, source-built components, exit0,
663.71s including build prerequisites; native mysh397.628032s, zero failed
processes. Overall Cloud status remains FAILURE from outer collector mismatch,
not a suite failure. Original uploaded summary is preserved; supplemental corrected
collector replay is a local service check, not another Cloud execution.

| Gate | Status / concrete evidence |
| --- | --- |
| Exact current base, clean scope, identities, bundle | PASS static; [INPUT-MAPPING.json](INPUT-MAPPING.json), [ready.bundle](ready.bundle), [pr.diff](pr.diff) |
| Translator and five fixtures vs8f0b / previous candidate | PASS identical bytes; [TREE-EQUIVALENCE.json](TREE-EQUIVALENCE.json) |
| New base toolchain lookup and source-built four components | PASS; [source certificate](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/source-input-certificate.json), [rustc](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/rustc.verbose.txt), [components](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/build-components.json), [make stdout](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/make-test.stdout.log) |
| Normal complete Linux make test, target chain, final exit | PASS exit0, zero failed processes; [stdout](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/make-test.stdout.log), [stderr](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/make-test.stderr.log), [exit](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/make-test-exit-code.txt), [resources](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/make-test-resources.txt) |
| Native five tests inside complete suite | PASS lines817–824 stdout, including exact-output assertion; [audit](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/proof-audit.json) |
| Contradictory precondition exact dead-code diagnostics + exit1 | PASS native assertion and direct diagnostic; [direct output](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/dead-diagnostic.stdout.log), [exit](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/dead-diagnostic-observed-exit.txt) |
| Fresh ordinary/shared caller MIR/AST on new components | PASS function/call/cleanup-bound; [audit](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/proof-audit.json), [shared MIR](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/affected/shared_cleanup/normal-mir.txt), [shared AST](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/affected/shared_cleanup/verified-ast.txt), [forget AST](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/affected/forget/verified-ast.txt) |
| Historical baseline orphan, false-post diagnostics / original expected failures | Applied prior8dd10da5 evidence with exact translator/.rs/compiler correspondence; [PRIOR-EVIDENCE.json](PRIOR-EVIDENCE.json). No new-base baseline execution claimed |
| Historical five upstream targeted regressions | Applied prior38b9ad73; native full suite now also runs upstream Rust tests. ignore_unwind_paths receives no unwind credit |
| Previous native full Rust executions | Prior f7c56eca /43b2f7fc PASS on old base/registration; not substituted for new execution |
| Rocq / Java AST server / assignments / solver conditionals | Rocq absent, Java server disabled, assignments directory absent: штатные skips. Legacy ifz3 disabled in upstream vfconfig; Z3v4.5-enabled cases run. [presence](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/selected/conditional-components.json), [NORMAL-CONDITIONALS.json](NORMAL-CONDITIONALS.json) |
| Original outer collector | FAILURE: obsolete cases/* mandatory glob, stale default tool-profile text; [uploaded summary](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/summary.json), [uploaded manifest](evidence/e7724679-b9c0-4526-ac63-1e8020b4114f/manifest.json). Raw source-bound audit/receipts take precedence over that default label |
| Corrected collector / immutable archive replay | Supplemental service result in [COLLECTOR-REPLAY.json](COLLECTOR-REPLAY.json); no recompilation or altered execution inputs |
| macOS / Windows / other CI configurations | NOT_RUN this session |
| Actual generic mem::forget/caller proofs | Separate proof task, not mandatory reacceptance |
| Upstream publication / acceptance | NOT_PUBLISHED / NOT_ACCEPTED |

Historical650s attempted run remains INCOMPLETE_TIMEOUT, not NOT_RUN or a
candidate defect. Existing immutable packages retain their original contents.
