# R23 actual `as_mut_ptr` callee projection

Status: implementation candidate; compiler API/build and proof acceptance remain
unverified. This is an opt-in, read-only projection of the actual standard
library callee MIR onto the existing caller call record.

## Defect and applicability

The source adapter needs evidence about what `slice::as_mut_ptr` actually does.
The pinned root standard library has no exported source body or contract for
that method. Replacing the call using a presumed summary would therefore grant
unchecked authority. Under `SMALLSORT_R23_SOURCE_ARRAY_BORROW=1`, the exporter
may query `tcx.optimized_mir(def_id)` only when the actual call operand is an
FnDef whose compiler-resolved definition path is exactly
`core::slice::<impl [T]>::as_mut_ptr` (including the pinned compiler's exact
canonical path check). It does not alter the selected caller MIR, query, or
borrow-check hook. The default path emits no new field.

## Invariants

- Identity is the actual `DefPathHash` and def path; `optimized` phase and a
  debug-body hash are navigation/integrity metadata, never body-equivalence
  evidence.
- The descriptor carries instantiated function signature and substitutions,
  every actual local ID/type, every statement in every basic block, the exact
  block and statement counts, and each block's actual terminator and cleanup
  bit. Existing `Ty`, `Place`, `Statement`, and `TerminatorKind` encodings keep
  operands, casts, kinds, and source/target types structured.
- No step is filtered or normalized during export. Unsupported calls,
  branches, or commands remain visible in the body. If a compiler body cannot
  be queried or completely represented, the optional descriptor is absent;
  absence is not acceptance. The consumer must require the complete supported
  shape and compare it with the checked helper body.
- Only the actual single-return-block pure local Copy/Move/cast projection can
  be considered by the downstream checker. This exporter does not emit a
  success flag, semantic summary, or authority-bearing string.
- One descriptor is attached only to the matching original call. Other calls,
  source cases, and all hand-built old fixtures default to `Nothing`.

## Schema and builder interface

Add optional `FnCallData.r23SliceProjection`. Its descriptor contains actual
callee identity/hash, phase/hash, generic substitutions, instantiated inputs
and output, local declarations, complete block list, explicit counts, and
separate unavailable/unsupported reasons. The
builder API is a read-only helper called from `encode_fn_call_data` with the
actual `func` operand and current `TyCtxt`; it resolves the FnDef, gates on the
environment variable and exact path, queries `optimized_mir`, and invokes the
existing type/place/statement/terminator encoders. It never consumes or
rewrites the caller body. Expected descriptor size is tightly bounded by the
single known standard method and is emitted only at an opted-in matching call.

## Controls and validation

Static controls: env unset; wrong function operand/path; non-FnDef; matching
callee with unavailable MIR; zero/multiple blocks; calls/branches; malformed
or non-pure body; and unchanged old fixtures. Only an exact matching actual
callee with a complete body is attached. Existing synthetic `FnCallData`
records initialize the new field to `Nothing`.

No local compiler, exporter, decoder, refiner, verifier, Cargo, OCaml, or tool
execution is permitted for this task. Schema/code generation compatibility is
therefore unverified and must be checked through the authorized Cloud path by
the integrating owner.
