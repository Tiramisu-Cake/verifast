# Draft — do not publish

Title: [Rust] Keep ManuallyDrop::new identity CFG successors consistent

`ManuallyDrop::new` is lowered to an assignment and normal goto. When Rust MIR
also lists an unwind cleanup successor, the translator currently includes that
successor in its block traversal even though it emits no unwind edge. A minimal
generic forget body reaches normal return and leak checking, then fails mandatory
dead-code checking on the orphan cleanup AST node.

Track this exact identity lowering per call and omit its extra unwind successors
only when a normal goto was emitted. Other calls and shared cleanup reached by
a genuinely unwind-capable operation keep their existing paths. Dead-code,
postcondition and resource checks remain active. The recognized standard-library
constructor only moves its value into the wrapper; it runs no destructor or
user callback. This change retains the existing trusted identity representation.

Includes a minimal generic reproducer, ordinary/shared unwind positive controls,
false normal and shared-caller unwind posts, and a separately runnable
contradictory-precondition dead-code control. No other Challenge 8 patch,
exporter, schema, refiner, spec or kernel change is required.

Validation: Cloud Build 8dd10da5-8a6b-40d7-88e2-7f4271324f17 completed the
source-built baseline/candidate focused gate at infrastructure/source
cf938bb31348c598de3d261f4169fa13a4bd11ab and tool/tests
8f0b701e9f2a3da124372c5d37d4cda408d45001. The integrity-verified archive is
723a0e08ed79880e1d94e5bb3e3a4222c8fef0f18d90fd3830e1b0854cb55c76.
Baseline forget reproduces the concrete orphan cleanup after normal return/leak;
candidate forget passes. Function-bound MIR and caller AST retain ordinary and
shared-cleanup unwind routes. False normal/unwind diagnostic copies reject at
the exact marked posts; original should_fail fixtures complete with mandatory
dead-code checks enabled. A contradictory precondition still rejects dead code.
The false-unwind fixture supplies a normal-first tail expression so expected
failure traversal leaves no artificial unvisited normal-return/goto statement;
a positive mirror uses the same runtime shape and truthful resource posts.

See [current Cloud result](../../cloud/verifast-mdnew-validation-20261009.md) for
upstream targeted regression results and their exact native test options. Full
upstream suite and consumer integration remain NOT_RUN. The refiner has known
unwind correspondence TODOs; its exit0 did not substitute for structural CFG and
false-unwind checks. Exact recognized names are processed after existing function
specialization; this patch does not add raw-DefId hardening.

Proposed code history: upstream f76012fb518703b1d98e243ac4f487f16877cfcb →
227dc163117e85d89fb1877bfc1e239a0628e5ab (unchanged transplant) →
1435539475fdaa7810bc2bc780fba0514f765f48 (focused consolidated tests) →
fc03ad9e5ab3404398404f3bba9d7bcacec01c43 →
8f0b701e9f2a3da124372c5d37d4cda408d45001 (normal-first tail-expression controls).
Keep maintainer organizational commits out of the upstream PR. Publication
requires separate owner authorization after validation.
