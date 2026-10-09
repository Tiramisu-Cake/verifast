# Historical Cloud validation plan

Current execution and exact updated pins are recorded in
[focused validation checkpoint](../../cloud/verifast-mdnew-validation-20261009.md).
The plan below preserves its original preparation scope and authorization status.

This was a recipe specification, not permission to submit. No Cloud Build,
role registration, dispatcher change, ledger or consumer pin was made. Before
execution the owner must authorize a phase, its own budget/deadline/ledger for
`verifast`, reviewed lane and pinned infrastructure revision. Preserve the existing
v2 coordinator: two project queued/running/unresolved builds total, one per owner
and ledger. Never inherit select/merge authorization.

## Immutable inputs

| Input | Exact identity |
| --- | --- |
| Baseline tool source | f76012fb518703b1d98e243ac4f487f16877cfcb |
| Candidate translator commit | 227dc163117e85d89fb1877bfc1e239a0628e5ab |
| Candidate with final tests | 1435539475fdaa7810bc2bc780fba0514f765f48 |
| Tool tree | Resolve from the preceding exact commit; also pinned in package manifest |
| Proof source/instructions/recipes inspected | 0ecff7ee7e6fd5d88082915252cae5dd2395bf93 (S) |
| Historical independent harness source | e6c02f22420ba4ff6a77e39c9610708a6096e7d7 (O1) |
| Std base | cd371e035c7e573760c43bf934d53e8118ee3e7d |
| Original tool patch | source.patch, SHA256593d09405379974ffbc475c2e0b65d648d8a6913f55b765dd0c3bebdc0922781 |
| Rust toolchain | nightly-2026-09-25, historical rustc full commit f7575a9da8e4a4fca3b5668d5a2ea7476db44b3f |
| Platform | x86_64-unknown-linux-gnu, Ubuntu22.04 |
| Dependency archive | vfdeps-adf88dc-linux.txz, SHA2568d022c93d51a1d13ec1e782d767c60462405f6865d5ee416f82d6234e93ee580 |
| Decoder source | btj/capnpc-ocaml-decoder 2d6606d9b59cd0c88a66729f3f076c10c0c8e0b2 |
| Historical stock26.10 distribution | SHA2565ad2a65997457fd5996a27f93107ef7e52c90c0d12b63b6e67f7acbc73e90efd |

Actual versions/binary/dynamic-library/spec digests must be recorded at build time;
these archive pins do not assert the new binary equals the historical console.
Build source baseline and candidate console in the same permitted environment
using the console target `make -C TOOL/src ../bin/verifast WITHOUT_LABLGTK=yes`.
Use stock pinned exporter/refiner/specs only with an explicit component audit, or
build their identical source components and record resulting digests. Record the
choice; do not silently mix profiles. Upstream `build.sh`, setup script and full
`testsuite.mysh` checks run only in Cloud once minimal gates pass. A ready bundle
with sufficient regression evidence may be reused after version, composition,
provenance and digest checks; rebuild/repeat for a recorded concrete reason.

## Focused baseline/candidate gate

Use the **same test bytes from candidate 14355394…** against both tool sources;
copy cases into an isolated Cloud evidence directory so the baseline need not
contain the newly authored test files. Root path:
`tests/rust/purely_unsafe/manuallydrop_new_cfg/`.
All commands below are future Cloud commands, never VPS commands.

| Case / command | Baseline expectation | Candidate expectation / required observation |
| --- | --- | --- |
| `verifast forget.rs` | exit1 orphan dead code after normal return/leak | exit0; body/normal return/leak checked; no orphan cleanup emitted |
| `verifast shared_cleanup.rs` | exit0 | exit0 for actual `new`, ordinary caller and shared caller; both feasible outcomes with token closure |
| `verifast -allow_should_fail false_normal_post.rs` | May stop on the old CFG defect; no negative credit then | exit0 only because sole `Cannot prove false` is on marked normal post in `forget_false_normal_post` |
| `verifast -allow_should_fail shared_false_unwind.rs` | intended rejection at marked unwind post | same intended rejection in `shared_cleanup_false_unwind_post`; earlier frontend/error is inconclusive |
| `verifast dead_code_pre.rs` | exit1 dead code at whole function | same exit1, no target-body execution; do not register as a positive mysh case or use allow_dead_code |

Capture verbose/timed proof output in addition to mysh exit status. Run the two
negative files without `-allow_should_fail` as diagnostic copies, expecting exit1
at their exact annotated post lines, and ensure no unrelated errors occur first.
Capture both NORMAL and readonly export, decoded MIR and source/refinement checks
using the existing harness mechanics from S `check-stock-2610.py` and
`check-forget-generic.py`. Preserve exact source and ghost-stripped bytes. Verify:

- `forget`: typed constant genuine ManuallyDrop::<T>::new, one Move of T,
  normal target present, cleanup action present in pinned MIR; original normal
  assignment/goto unchanged, unreferenced cleanup omitted from final caller AST.
- `shared_cleanup`: locate its MIR body by defPath, verify MDnew and actual `new`
  both reference the same cleanup BB (not a hardcoded number), retained cleanup
  is marked cleanup and reaches UnwindResume. In that caller's AST, the ordinary
  call outcome switch must have an unwinding arm whose goto reaches that label
  and the corresponding unwinding return. Confirm ordinary caller Continue path
  separately. Never satisfy the check using a callee AST or whole-unit substring.
- If the compiler's MIR shape differs, report a shape mismatch and inspect it;
  do not weaken the structural gate or count an unintended negative.
- All other calls and identity lowerings are bytewise unchanged in the source
  diff; inspect the effective specialization declarations/specs and ensure no
  remapping into MDnew recognition exists. No ignore-unwind/dead-code suppression.
- Keep post, leak, thread, validity and mandatory dead-code checks enabled. The
  present refiner leaves unwind correspondence TODOs, so refinement0 alone
  cannot be the source/MIR-unwind acceptance criterion.

Retain historical 11-unit O1 controls only to the extent not covered by these
cases and existing applicable evidence (not a new wide matrix). If reusing the
old binary/evidence, verify its exact hash/component profile and document why
it applies. The new test and consumer inputs still require their own gates.
After focused results, run upstream Rust/full test suite at exact tool SHA as
required by upstream guidelines and audit affected non-Rust regressions. Stop
and assess new failures instead of repeating unchanged tests automatically.

## Actual consumer check, without admitting a merged profile

Nearest reproducible actual-source consumer for this component is the exact
stdlib `mem::forget` body. Use S `library/core/src/mem/mod.rs` and
`research/challenge-8/check-forget-generic.py::FORGET_SOURCE/FORGET_BODY` to
compare the generic adapter's body byte-for-byte to that committed body. Preserve
unrestricted Sized T and the stated token/false-unwind contract; do not infer a
SAFE generic summary or erase ownership obligations. Hash source, proof adapter,
exported MIR and complete normal/unwind/return/leak/dead-code outputs.

For proof-agent integration, owner must choose/publish a frozen actual pointer
selector/helper caller case from S and enumerate its already required experimental
components. Compare that same profile with this CFG component off/on, running
actual callee before caller and preserving full posts. Record exact source/proof,
spec and profile SHA; a later unsupported primitive can show the blocker moved,
not a completed theorem. This integration is separate from standalone tool
validation and pin adoption. No other component is transplanted or developed in
this session; no select/merge profile combination is proposed.

## Minimal delivery gap and bounded next infrastructure task

Inspected S files:
`cloud-build/source-input.py::{validate_recipe,make_payload,repo_record,restore_archive}`,
`control.py::{config,make_payload}`, `run-proof.sh` and
`exact-infra-transport-controls.py`. Current transport has infra/proof and optional
baseline records, no native third tool repository. Recipes accept regular blobs
under `research/challenge-8/` or `library/core/`; the review-package path outside
that prefix cannot be selected directly by current validate_recipe.

The smallest addition can **avoid changing the generic dispatcher/transport**:

1. Deliver the already prepared incremental `tool-candidate.bundle` plus manifest
   as committed ordinary proof-input blobs under
   `research/challenge-8/verifast-input/<tool-SHA>/`, by a separately authorized
   infra/source owner. Add their exact paths to a new recipe
   `cloud-build/recipes/verifast-mdnew-cfg.json`; pin base/tool commit, root tree,
   bundle digest and test hashes in the committed manifest. The bundle contains
   the original candidate commits/trees/blobs and requires exact upstream base;
   it contains no config, hooks, credentials or working-tree data.
2. Add a bounded `cloud-build/run-verifast-mdnew-cfg.sh` entrypoint and a light
   restore helper (new `cloud-build/restore-verifast-input.py`, if helpful).
   Reuse the current exact upstream source checkout path, assert base SHA,
   verify bundle digest and prerequisites, fetch the named bundle ref, checkout
   exact candidate commit in the disposable Cloud tool directory and attest
   HEAD/tree/selected bytes. Missing/mismatched input fails before compiler/proof.
   Build or restore the provenanced tool kit; preserve source identities and
   component hashes. Do not synthesize a Git commit after patch application.
3. Existing `run-proof.sh` recipe routing can invoke this entrypoint; inspect
   before changing it. Preserve source-input schema, coordinator and peer recipes.
   Native third-repository support in source-input/control is an alternative
   larger change, not necessary merely to deliver this small incremental bundle.
4. Tests for this infrastructure change: exact base + bundle restores original
   tool commit/tree/blob IDs; wrong digest/ref/prerequisite/tree/test path rejects;
   no working-tree/config/hook data enters; payload is within the existing <=191
   source-part limit; archive/input/evidence receipts bind bundle and tool hashes.
   Here bundle verify/list-heads and an isolated Git-only restore were checked;
   these do not execute a compiler or count as lane acceptance.

Owner/phase/ledger registration and reviewed lane allowlist in control.py need
separate authorization and budget before any Build. Do not begin that implementation
or dispatcher integration under this review assignment. Future infra/proof commits
must be frozen and published before requesting admission; no SHA is invented here.
