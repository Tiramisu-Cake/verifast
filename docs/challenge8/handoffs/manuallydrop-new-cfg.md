# MDNEW-CFG-2610: independent review

Verdict: **READY_FOR_CLOUD_VALIDATION**. Static review finds no blocking defect
in the exact pinned `ManuallyDrop::new` path. This is a prepared candidate,
not a qualified distribution, accepted consumer pin, upstream acceptance or a
new proof result. New builds and tests are **NOT_RUN**.

## Source and ownership

- Proof source selected for this review: `Tiramisu-Cake/verify-rust-std`,
  `0ecff7ee7e6fd5d88082915252cae5dd2395bf93` (S), read through committed objects;
  the source patch is `research/challenge-8/verifast-manuallydrop-new-cfg-2610.patch`.
- Patch introduced by `e6c02f22420ba4ff6a77e39c9610708a6096e7d7`.
  S history contains no subsequent change to this path. Orienting snapshot
  `70e5dfa3917a36620b0ac6a1734a677f97332db4` has identical bytes.
- Git blob `7c4403b143d69b03b24e437fd4320776b51ca619`;
  SHA256 `593d09405379974ffbc475c2e0b65d648d8a6913f55b765dd0c3bebdc0922781`.
  S and the patch were accessible through the authorized GitHub API.
- Upstream base and fetched master: `f76012fb518703b1d98e243ac4f487f16877cfcb`.
  Targeted history search and GitHub PR/issue searches found no superseding fix;
  PR #420 is the historical original Drop/ManuallyDrop support, already ancestral.
- Unchanged transplant: `227dc163117e85d89fb1877bfc1e239a0628e5ab`, local branch
  `challenge8/manuallydrop-new-cfg-review`, worktree `/root/verifast-manuallydrop-review`.
  No adaptation or new implementation fix to the original patch was made.
- This worktree is the sole owner of the **review variant and its new tests**.
  No ownership transfer of the proof agent's experimental profile was confirmed;
  the original owner remains active there. No consumer pins or proof files changed.
  Final consolidated tests/tool tip: `1435539475fdaa7810bc2bc780fba0514f765f48`,
  branch `challenge8/manuallydrop-new-cfg-upstream-candidate`; parent is the
  unchanged transplant. Its tree equals development tip
  `9209cc9dfdf9f70df5a2ee9b790dc7a66caf5cca`. Development test commits
  `294bb72374c6c12842a822c76ec15fa080044513`,
  `c124dde2d21e7dd4084af14458e37552cc7d3dd8`,
  `3d5f2abf22b5ae47d64bce90ec86498ce9c42d14` and `9209cc9d…` are retained
  on the review branch; only the final two focused commits are proposed upstream.
  Test preparation defects (internal panic API, fixture isolation and stray patch
  text) were corrected before checkpoint; the source translator was unchanged.

Review by maintainer, with independent GPT-6 Sol CFG investigation and GPT-6 Luna
existing-evidence inspection. Tests were prepared by a separate Luna worker and
statically reviewed by the maintainer; they have not acquired execution credit.

## Exact defect and change

Line references here are to the upstream base unless stated otherwise.
`src/rust_frontend/vf_mir_translator/vf_mir_translator.ml`:

| Symbol / location | Observation |
| --- | --- |
| `translate_fn_call_rexpr`, 2388–2409, 2592–2598 | A typed constant generic callee is canonicalized/specialized; exact `std::mem::ManuallyDrop::<T>::new` is already lowered to `FnCallResult arg`. |
| `translate_fn_call`, 2699–2758 | With a normal target, `FnCallResult` emits an assignment and `Mir.GotoTerminator` to the normal successor. It emits no switch on an outcome and no unwind statement. |
| `translate_unwind_action`, 2647–2667; call tail, 2796 | A MIR cleanup contributes its BB ID to `unwind_targets`; the old tail appends it despite the absence of an emitted unwind edge for the identity operation. |
| `find_blocks`, 3879–3892; body assembly, 5217–5225 | Traversal follows advertised successors, not just emitted gotos, so an orphan cleanup block enters the AST and mandatory dead-code checking rejects it. |
| candidate tail, 2800–2810 | The per-call marker removes only these extra targets when the result is `FnCallResult` and the terminator is normal `GotoTerminator`. |

`src/vfconsole/vfconsole.ml:266–285` records statement locations, removes executed
locations and exits1 for unexecuted statements unless explicitly suppressed. That
code and its default behavior are untouched.

This is a CFG bookkeeping repair. It neither disables dead-code checking nor
marks a failing assertion as admissible. The existing dead-code checker correctly
reports an AST node it cannot execute; the fix prevents an impossible incoming
edge from causing that node to be emitted as reachable code.

Exporter `src/rust_frontend/vf_mir_exporter/src/lib.rs:2504–2521,2580–2624`
serializes the MIR `Call` target and `UnwindAction` unchanged. A syntactic MIR
cleanup successor is conservative call metadata, not proof that this particular
callee can unwind. At S, `library/core/src/mem/manually_drop.rs:180–182` is exactly
`pub const fn new(value: T) -> ManuallyDrop<T> { ManuallyDrop { value } }`.
Constructing/moving that wrapper executes no user code or destructor. Dropping the
ignored wrapper does not drop T. Argument evaluation happens before this call in
MIR; the translator translates argument operands first (2347–2351), and earlier
calls/argument computation retain their own unwind edges. The patch changes no
ownership interpretation, assignment, temporary binder, pre/postcondition, heap,
solver state, validity check or destructor model. Correspondence of the existing
identity representation and Rust move/destructor semantics remains trusted.

## Applicability and retained paths

The marker is a fresh false ref for each call, set true only in the already
recognized exact standard-library name branch. `UnsafeCell::new`, ManuallyDrop
deref/deref_mut and all other `FnCallResult` cases retain previous behavior.
Moved/indirect callees and zero-generic-substitution calls are regular
`FnCallOutcome`; closure-substitution early lowering leaves the marker false.
`target=None` gives `EncodedTerminator`, so it is explicitly outside the fix.
Unwind Continue/Terminate/Unreachable and emitted statements are not broadly
removed. A genuine `FnCallOutcome` keeps its unwind switch/statements and successor
inventory. Shared cleanup is retained whenever reachable through another such
operation; normal successors are unchanged, including any coincident target ID.
The marker is translator-local bookkeeping, not mutable symbolic execution state.

No other Challenge 8 patch is needed to apply or understand this component.
It changes one translator file and applies cleanly to upstream alone. Larger
select/merge profiles, SAFE forget summaries, MaybeUninit, guard ownership and
actual caller proofs have separate dependencies and are not admitted here.

## Findings and Cloud gates

1. **Required validation improvement, not an implementation defect:**
   `research/challenge-8/overnight/check-cfg.py:24–28` searches the entire AST for
   `ReturnStmt`/`unwinding`. Bind the check to the shared caller, its decoded MIR
   cleanup target and the genuine call's translated goto. Add a false-unwind
   postcondition on that caller; the old negative covers only ordinary calling.
2. **Inherited recognition boundary:** the matched name is after `fn_specializer`
   (2398–2400; resolution 7959–7979,8034–8044), not a fresh raw DefId check.
   An invalid specialization redirect could already trigger identity lowering.
   S research inputs have no specialization redirect to ManuallyDrop::new in the
   targeted search; verify the complete effective accepted input/spec profile in
   Cloud. Do not claim this patch hardens arbitrary custom specialization inputs.
3. **Existing refiner limitation:** `src/refinement_checker/refinement_checker.ml`
   1804 and 2548 (also Drop at 2558) leave unwind processing/correspondence as TODO.
   A refinement exit 0 and equal exported MIR cannot alone discharge soundness
   of the changed translated unwind CFG. Read the function-bound AST/MIR and
   negative evidence in addition. No refiner change is part of this candidate.
4. New tests need compiler/frontend validation and exact error-location checks.
   They deliberately remain NOT_RUN; any unrelated setup error is inconclusive.

## Existing evidence and limits

See [evidence review](../reviews/manuallydrop-new-cfg-20261009/EVIDENCE.md) and
[evidence inventory](../reviews/manuallydrop-new-cfg-20261009/evidence-inventory.json).
Authorized API retrieval obtained O1 run `37698481357`, job `113055959913`, artifact
`11517185187`. Its digest was independently matched; substantial original logs,
AST and decoded MIR were read. Stock forget actually executes normal return/leak
before a whole-function-span dead-code diagnostic; the orphan AST node shares
that source span. Candidate forget succeeds. Both profiles preserve other
positive, false-post and contradictory-pre outcomes. Shared caller AST explicitly
retains `unwinding -> goto 3` and label 3 returning `unwinding()`.

The saved checker reports accepted **experimental** stock+CFG profile and 11 cases;
this review confirms observations of those saved files, not personal reproduction.
No actual helper or sort4 theorem, new tool delivery or consumer acceptance follows.
Fresh source-built baseline/candidate, new tests, complete upstream suite, actual
consumer integration, optional formal/Rocq correspondence and final qualification
have not been executed in this session.

## Upstream suitability and next step

Suitable for a standalone upstream PR after Cloud validation: narrow single-file
repair, no project-specific spec/kernel dependencies, focused tests and explicit
retained-unwind/dead-code controls. The [PR draft](../reviews/manuallydrop-new-cfg-20261009/PR-DRAFT.md)
is prepared and must not be published under this assignment.
The [Cloud plan](../reviews/manuallydrop-new-cfg-20261009/CLOUD-VALIDATION.md)
contains exact inputs, acceptance criteria and the smallest delivery addition.
Next assignment: implement and service-test the pinned incremental tool-bundle
restore lane under a separate infrastructure authorization, without dispatching
proofs until owner `verifast` has its own approved phase and budget.
