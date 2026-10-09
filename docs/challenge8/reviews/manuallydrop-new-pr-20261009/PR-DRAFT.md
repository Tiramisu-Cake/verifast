# Proposed PR — review only, never submitted

Target: `verifast/verifast`, base branch `master`.
Base: `f76012fb518703b1d98e243ac4f487f16877cfcb`.
Current upstream master (2026-10-09 19:36:28 UTC): `0a83dba42db7ce0b445034ece5298afe980e57dc`.
Prospective merged tree `70478c6077d3b9d241ce7e49b8666742a227fd13`: clean static merge, execution NOT_RUN.
Head branch: `upstream/manuallydrop-new-successors` (local/bundle only).
Head: `da4beb61a6c2dd0e80fe4a74c5c230f3adac7cab`.
Tree: `50481095a79cb8f517fb61c0a4aa5d026b591b91`.
Head repository: future user-approved fork; none created.

Title: [Rust] Keep ManuallyDrop::new identity successors consistent with the CFG

Body SHA256: `061c0a60da843851f4f15e81f72cd1cd7bd2ba3e5d35d14760124fa20d2357d9`.
Approve must cover that exact head/title/body. This draft is a file for review and grants no publication authorization.

## Exact body

`ManuallyDrop::new` is already translated as an identity operation: an assignment
followed by a goto to the normal successor. Rust MIR may nevertheless list a
conservative cleanup successor for that call. The translator currently adds this
cleanup to its successor inventory even though it emits no unwind edge to it.
Block discovery then emits an orphan cleanup, and mandatory dead-code checking
rejects an otherwise valid generic `forget` body after its normal return.

For example:

```rust
pub unsafe fn forget<T>(t: T)
//@ req thread_token(?tid) &*& tid == currentThread;
//@ ens thread_token(tid);
//@ on_unwind_ens false;
{
    let _ = std::mem::ManuallyDrop::new(t);
}
```

Track this exact existing constructor lowering per call and omit its additional
unwind successors only when the result is `FnCallResult` and a normal goto was
emitted. Other calls retain their unwind statements and successors. Cleanup
shared with a genuinely unwind-capable call remains reachable through that call.
Argument evaluation retains its own earlier MIR operations and unwind edges.

The constructor moves its argument into a wrapper; it runs no user callback or
destructor. This retains the existing trusted identity representation and does
not change contracts, resource/lifetime checks, the exporter, specs, or kernel.

The registered Rust regressions cover:

- generic `forget` without an orphan cleanup;
- ordinary and shared-cleanup callers with real unwind paths, including an
  ordinary function named `new`;
- separate false normal and false unwind postconditions using `should_fail`;
- a contradictory-precondition fixture rejected by mandatory dead-code checking;
- a positive control with the same runtime shape as the false-unwind fixture.

The false-unwind control uses a normal-first tail expression. This lets symbolic
execution visit the shared normal return before the expected unwind error ends
that verification scope, and avoids an artificial unvisited continuation goto.
Its false unwind postcondition and actual panic path remain unchanged. No focused
fixture disables unwind or dead-code checking. Native `mysh` uses `!` for the
expected dead-code failure; this checks a nonzero exit, while the validation audit
also checks the exact dead-code diagnostic.

Build and reproduce with the normal repository tooling:

```sh
./setup-build.sh
./build.sh
repo=$(pwd)
(cd tests/rust && PATH="$repo/bin:$PATH" "$repo/bin/mysh" -cpus 1 < testsuite.mysh)
make -C src test
```

The implementation was originally developed in `Tiramisu-Cake/verify-rust-std`
commit `e6c02f22420ba4ff6a77e39c9610708a6096e7d7` and used in its experimental
profile before this separate upstream preparation. The translator implementation
is unchanged; this branch consolidates the tests and native registration.

The new source-built head passed all five registered regressions and the full
Rust suite in the native harness (0 failed processes in both runs). The broader
Linux `make test` reached a 650-second cap during the root suite and remains
incomplete; it must finish before submission readiness is claimed. Source-built
baseline/candidate validation of identical translator and Rust fixture bytes
already reproduced the baseline orphan cleanup, accepted candidate `forget`, and
confirmed function-bound ordinary/shared unwind transitions. Exact false-post
failures and the contradictory-precondition dead-code failure were checked;
five existing upstream Rust regressions also passed with their native options.
Tests using `ignore_unwind_paths` carry no unwind credit.

This head uses the tested base f76012fb518703b1d98e243ac4f487f16877cfcb. During
preparation master advanced to0a83dba42db7ce0b445034ece5298afe980e57dc (#1039).
The changes merge cleanly and leave this translator and these tests unchanged,
but update Rust toolchain lookup. The combined master/head profile has not been
executed; merged-profile CI is required before merge acceptance.

These are bounded regression results, not a general soundness proof. The refiner
still has unwind correspondence TODOs; its exit 0 and equal exported MIR were
supplemented by checks of the affected caller CFG/AST and negative outcomes. The
existing constructor-name recognition follows specialization; this patch does
not add raw-DefId hardening.
