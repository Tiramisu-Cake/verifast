# Restore and reproduce

Prerequisite: checkout of verifast/verifast at exact base
f76012fb518703b1d98e243ac4f487f16877cfcb and ready.bundle with manifest digest.
These commands are for the reviewer’s configured build environment or a separately
authorized Cloud run. They were not executed on the VPS.

```sh
git bundle verify ready.bundle
git fetch ready.bundle refs/heads/upstream/manuallydrop-new-successors:refs/heads/review-mdnew
git switch review-mdnew
git rev-parse HEAD HEAD^{tree}
./setup-build.sh
./build.sh
repo=$(pwd)
(cd tests/rust && PATH="$repo/bin:$PATH" "$repo/bin/mysh" -cpus 1 < testsuite.mysh)
make -C src test
```

Expected head da4beb61a6c2dd0e80fe4a74c5c230f3adac7cab, tree
50481095a79cb8f517fb61c0a4aa5d026b591b91. The branch contains only the standalone
translator fix and registered regressions. Bundle metadata preserves original
Git commits, not a reconstruction with invented identity.

For a baseline reproducer, put reproducer.rs outside a clean base checkout and
invoke that source-built base console on it. Expected result is the concrete
orphan cleanup dead-code error after normal verification; the candidate console
accepts it. Keep identical fixture bytes/options/runtime components between sides.
Prior exact baseline/candidate execution is linked in CHECKS.md.

Focused commands from tests/rust/purely_unsafe/manuallydrop_new_cfg:

```text
verifast forget.rs
verifast shared_cleanup.rs
verifast -allow_should_fail false_normal_post.rs
verifast -allow_should_fail shared_false_unwind.rs
verifast dead_code_pre.rs
```

First four complete successfully on candidate. Last exits1 with whole-function
dead code from its contradictory precondition. No arbitrary nonzero is sufficient
for that negative. Diagnostic copies of the two false-post fixtures remove only
the should_fail marker while preserving lines; they must reject the normal false
post at3 and on_unwind_ens false at14, respectively. Do not weaken the original
postcondition or mark unrelated errors as expected.

Decoded MIR and translated AST checks bind to the caller function and call’s
actual cleanup target: ordinary Continue and shared cleanup3 must reach unwind
return. They are not whole-file marker checks. Refiner’s existing unwind TODO
means its successful exit alone is insufficient. The native suite checks its
registered runtime/contract controls; prior structural captures apply by identical
translator/fixture inputs, and are not invented execution at this new SHA.
