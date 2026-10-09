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

Validation: static source review, clean application and diff checks completed.
An existing exact-patch O1 artifact was inspected (run37698481357); it shows the
stock failure and candidate success, with unchanged source/exported MIR and
retained ordinary/shared unwind paths. This is historical experimental evidence,
not reproduction of these new commits. Builds, new fixtures and upstream test
suite remain NOT_RUN, pending authorized Cloud execution. The refiner has known
unwind correspondence TODOs; its exit0 is not a substitute for structural CFG and
false-unwind checks. Exact recognized names are processed after existing function
specialization; this patch does not add raw-DefId hardening.

Proposed code history: upstream f76012fb518703b1d98e243ac4f487f16877cfcb →
227dc163117e85d89fb1877bfc1e239a0628e5ab (unchanged transplant) →
1435539475fdaa7810bc2bc780fba0514f765f48 (focused consolidated tests).
Keep maintainer organizational commits out of the upstream PR. Publication
requires separate owner authorization after validation.
