# Checks for the proposed upstream branch

| Check | Status / evidence |
| --- | --- |
| Current upstream, equivalent fix/open PR search | PASS read-only; initiallyf760, finally0a83/#1039; translator/tests unchanged and clean merge; UPSTREAM-ADVANCE.json |
| Current master + prepared head merged profile70478c6 | NOT_RUN; frontend/refiner toolchain lookup changed; fresh merged CI required before merge acceptance |
| Base-to-head scope, author/committer and bundle | PASS static; INPUT-MAPPING.json, pr.diff, ready.bundle |
| Translator, specs and five fixtures equal verified8f pin | PASS byte/tree comparison; only README and registration differ |
| Baseline orphan cleanup in generic forget | PASS applied prior focused Build8dd10da5; exact dead-code outcome |
| Candidate generic forget | PASS applied prior focused Build8dd10da5 |
| Ordinary and shared unwind MIR/caller AST/CFG | PASS applied prior focused Build8dd10da5; exact function/call/cleanup/return bound |
| False-normal and false-unwind diagnostic copies | PASS applied prior focused Build8dd10da5; exact target postconditions |
| Original should_fail controls, no unexplained extra errors | Candidate two originals and baseline false-unwind original PASS; prior Build8dd10da5 |
| Baseline false-normal original allow fixture | NOT_RUN under prior focused plan: known baseline orphan cleanup; its target diagnostic was checked separately |
| Mandatory dead-code and matching positive control | PASS applied prior focused Build8dd10da5 |
| Five existing targeted upstream regressions | PASS applied prior Build38b9ad73, exact native options; ignore_unwind_paths gives no unwind credit |
| New native registration, exact dead-code audit | PASS new Buildf7c56eca and Build43b2f7fc; FINAL-NATIVE-REPLAY.json binds exact source/hash/diagnostic |
| Full tests/rust/testsuite.mysh | PASS new Buildf7c56eca (109.25s) and Build43b2f7fc (144.43s), both0 failed processes; verified stage receipts |
| Linux make test (root suite + assignment solutions + JSON) | INCOMPLETE / NOT_RUN_TIMEOUT: firstf7c56eca lacked cmake; repeat43b2f7fc with pinned dependencies reached650s cap during root suite. Required completion remains a preparation blocker |
| macOS, Windows, Ubuntu24/Rocq, aarch64, flake CI | NOT_RUN here; later upstream CI, no PR authorized |
| Hidden/org mandatory branch checks or legal agreement | UNKNOWN public policy; no agreement signed |
| Consumer proof/profile qualification and actual mem::forget obligations | Separate proof task; no repeated acceptance required for unchanged patch |
| Upstream PR/fork/issues/comments/messages | NOT_PUBLISHED, explicit later approve required |

Prior immutable links, input pins and archive hashes are in PRIOR-EVIDENCE.json.
Native mysh ! alone proves only a nonzero child exit; the fresh audit must bind
its exact dead-code diagnostic to that specific command trace. Original
should_fail fixtures must execute with their native allow_should_fail option.
Source equivalence applies prior outcomes to identical significant inputs; it
does not invent a new Cloud run of this head or close the refiner unwind TODO.

Final verdict: **CHANGES_REQUIRED** for the unfinished mandatory Linux full-suite
check. No new semantic defect was established. Build43b2f7fc is SUCCESS because
its native/Rust gates passed; its explicit make_test=NOT_RUN_TIMEOUT is retained.
See [Cloud audit](evidence/43b2f7fc-f089-476b-8690-ef8ed84129ee/proof-audit.json),
[make log](evidence/43b2f7fc-f089-476b-8690-ef8ed84129ee/selected/make-test.log),
[Rust log](evidence/43b2f7fc-f089-476b-8690-ef8ed84129ee/selected/rust-testsuite.log),
and [native trace](evidence/43b2f7fc-f089-476b-8690-ef8ed84129ee/selected/native-registration.log).
