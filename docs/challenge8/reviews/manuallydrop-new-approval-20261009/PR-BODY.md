Generic `forget` can fail mandatory dead-code checking when Rust MIR gives
`ManuallyDrop::new` a conservative cleanup successor:

```rust
pub unsafe fn forget<T>(t: T)
//@ req thread_token(?tid) &*& tid == currentThread;
//@ ens thread_token(tid);
//@ on_unwind_ens false;
{
    let _ = std::mem::ManuallyDrop::new(t);
}
```

The existing identity lowering emits an assignment and normal goto, but the
successor inventory also advertises an unwind target. Block discovery therefore
introduces an orphan cleanup. This patch omits that additional successor only
for the recognized constructor when its lowering emits a normal goto. Ordinary
calls, argument evaluation and genuinely shared unwind cleanup retain their edges.

The registered Rust tests cover generic `forget`, ordinary/shared unwind callers,
false normal/unwind posts, mandatory dead-code rejection and a matching positive
control. The false-unwind fixture visits the normal branch first to avoid an
unvisited continuation after its expected error. The dead-code registration uses
mysh's existing exact-output assertion and requires the intended diagnostics plus
exit 1, so an unrelated early failure cannot satisfy it.

The complete Linux `make test NUMCPU=4` passed on candidate `bf63b7df`, based on upstream master `0a83dba4`, with source-built components and nightly-2026-09-25: exit 0, zero failed processes (11m 04s including build prerequisites). The registered tests and fresh ordinary/shared-cleanup MIR/AST checks passed. Rocq, Java-server and assignments checks were skipped under the suite's normal conditions; other platforms were not run.

Reproduce with configured build dependencies: `make -C src test NUMCPU=4`.
This preserves the existing trusted identity representation and constructor-name
recognition. It does not resolve the refiner's unwind correspondence TODO or claim
general verifier soundness.
