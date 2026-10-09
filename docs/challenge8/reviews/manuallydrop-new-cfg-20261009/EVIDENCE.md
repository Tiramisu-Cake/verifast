# Existing evidence read in this review

This is inspection/comparison of immutable saved evidence, not a new run or a
rerun of the old classifier. The review report at proof S
`0ecff7ee7e6fd5d88082915252cae5dd2395bf93`,
`research/challenge-8/OVERNIGHT-SELECT-SORT4-26.10.md`, first supplied O1 identifiers
and assertions. They were then checked against the authorized GitHub API and
actual artifact files. No meaningful log remains unavailable for this O1 review.
A separate attempted Cloud-bucket listing timed out; it is not the O1 provider
and is not evidence against the retrieved GitHub run.

- Run: https://github.com/Tiramisu-Cake/verify-rust-std/actions/runs/37698481357
- Proof input: `e6c02f22420ba4ff6a77e39c9610708a6096e7d7`.
- Job113055959913: raw decoded job log is
  `/tmp/verifast-review-20261009-evidence/job-113055959913.log`,
  SHA256 `0588a66fdc03b6ca5aae7a2ff5e4eeafcd7b7e5f6c65784db8e0aacce4299138`.
- Artifact11517185187, `overnight-cfg-37698481357-1`, 614457 bytes;
  downloaded ZIP `/tmp/verifast-review-20261009-evidence/overnight-cfg-37698481357-1.zip`,
  SHA256 `0cd026a65f9502aa85867d538f345eaf3f8392c67e85f14f02b8c5a5b86c109a`.
  This equals the digest returned by the GitHub artifact API; expiry2027-01-05.
- Extracted root: `/tmp/verifast-review-20261009-evidence/overnight-cfg-37698481357-1/`.
  650 files, including147 logs. File paths, byte counts and SHA256 digests for all
  files are in [evidence-inventory.json](evidence-inventory.json). Original logs
  are retained there/on the API artifact, not committed as new proof outputs.

## Direct observations from files

Environment/profile-hashes agree with the patch hash593d0940…, upstream f76012fb,
console bf9a0252…, unchanged exporter b00c75f4…, refiner b049c8d1…, std spec
2da7acfb… and schema f48fcf29…. Full hashes are in the inventory.
Rust is nightly-2026-09-25 (`f7575a9da8e4a4fca3b5668d5a2ea7476db44b3f`),
Cap'n Proto0.10.4, OCaml4.14.0. Historical stock release console is9b7650ad…;
the new local tool commit/bundle has not produced a binary in this session.

Each stock/candidate summary contains11 units. Five candidate positives are
u32, raw read, generic forget, ordinary unwind and shared cleanup. Four negatives
are u32/raw/forget false normal posts and ordinary false unwind. Two controls
are contradictory preconditions in u32 and forget. The stock classifications
agree except forget_positive, which is INCONCLUSIVE with verifier exit1.

Substantial original verifier logs, source and AST/MIR were read by the evidence
explorer; the maintainer also checked the causal forget logs and relevant
shared-cleanup/false-unwind/dead-code locations. Specifically:

- `stock/cases/forget_positive/full-verification.log` executes the target's normal
  return at16:2 and leak check, then reports only
  `verified/lib.rs(3,1-16,2): dead code`. The stock AST has the orphan unwind
  cleanup return at the same whole-function source span. This is not a failure
  to enter the normal function body or a missing safe-forget summary.
- `cfg/cases/forget_positive/full-verification.log` executes body, return and
  leak check without that orphan statement; full verifier exit0.
- `cfg/cases/shared_cleanup/normal-mir.txt` explicitly lists MDnew and the ordinary
  panicking call with `unwindAction=(cleanup,index=3)`. Block3 is cleanup and
  `UnwindResume`. In its caller AST, the call at27:14–38 has an unwinding switch
  arm with goto3; label3 returns `unwinding()`. Logs cover both returns and leak
  checks and finish with no errors. Ordinary caller separately retains Continue.
- `cfg/cases/false_unwind/full-verification.log` reaches the caller's unwind return
  and rejects the marked false unwind post at23:15–20 (`Cannot prove false`).
- `cfg/cases/forget_contradictory_pre/full-verification.log` does not execute the
  target body; it reports the whole-function and body-span dead-code diagnostics.
  The mandatory detector still rejects a vacuous precondition on the candidate.

Read-only comparison made66 byte-for-byte checks: original and annotated source,
NORMAL/readonly MIR binary and decoded text, for11 stock/candidate pairs. All
match. The saved root acceptance.json says `accepted=true`, `false_checks=[]`,
`actual_helper_proved=false`, `generic_safe_forget_proved=false`; root/acceptance
exit files are0. This confirms what that historical experimental checker recorded,
without promoting the checker result to an independent proof of translator
soundness or of a new source/profile.

## Limits which remain

The old report asserts full profile acceptance,147-log audit and104s elapsed.
The run/profile/files above are now observed, not merely report assertions; this
session does not reproduce the run or transfer its acceptance to new tests.
The checker tests its unwind AST marker globally, while function-bound inspection
and the new false-unwind control remain needed for robust future automated gates.
The stock refiner does not yet check Call unwindAction correspondence (TODO2548,
and process_commands1804; Drop unwind alsoTODO). Exported MIR equality protects
unchanged exporter output, not the identity-lowering soundness theorem.

Compiler-backed wrapper representation/move/destructor/no-unwind interpretation
is inherited trusted correspondence. Current exact recognized path is defensible
by source review, but arbitrary specializations and changed future std bodies
are not admitted automatically. New source-built tools, five new fixtures,
actual consumer integration and complete upstream regressions are NOT_RUN.
