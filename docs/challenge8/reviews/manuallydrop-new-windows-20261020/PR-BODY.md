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

The dead-code capture runs in an explicit `sh` helper so the exit-status capture
works with native Windows mysh, whose child commands use `cmd.exe`. The exact
expected diagnostics and exit-1 marker are unchanged.

The existing [fork CI matrix](https://github.com/Tiramisu-Cake/verifast/actions/runs/39339228464)
passed on candidate `ac6a63d5cad3a028e5d6f7ee4439169ba443468b`, based on
`0a83dba42db7ce0b445034ece5298afe980e57dc`: Ubuntu22, Ubuntu24 with Rocq,
macOS, Windows, the aarch64 Linux cross-compile check and flake-check. Build jobs
run the project's normal nightly build/test graph; its configuration-dependent
suite conditions still apply. Six release/upload-only jobs were skipped for this
fork-branch push. Run duration: 11m24s, attempt1.

Reproduce with configured build dependencies: `make -C src test NUMCPU=4`.
This preserves the existing trusted identity representation and constructor-name
recognition. It does not resolve the refiner's unwind correspondence TODO or claim
general verifier soundness.
