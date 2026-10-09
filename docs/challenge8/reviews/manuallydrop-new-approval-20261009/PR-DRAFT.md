# Exact proposed PR — awaiting user approve

Repository: verifast/verifast. Base branch: master.
Tested upstream base: `0a83dba42db7ce0b445034ece5298afe980e57dc`.
Local head branch: `upstream/manuallydrop-new-final-20261009`; head: `bf63b7dff2e053eea8541996d856fac4be11f6f1`.
Tree: `687ae7dab447c94c4b87362d3d880d959c89e3de`. No public fork or head repository exists.

Title: [Rust] Keep ManuallyDrop::new identity successors consistent with the CFG
PR-TITLE.txt SHA256: `dfa9b93e9368fdb751625483adfe217c476152f0fcd53694c3e42807f1c21b1c`.
PR-BODY.md SHA256: `c1b21d031078e12bfacce8301aee7ec9e9f552e97e4542de2d3cf96c9febb10c`.
Approve must cover these exact head, title and body. No PR/draft was submitted.

## Exact body

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
