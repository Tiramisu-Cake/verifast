# ManuallyDrop::new CFG regression

`forget.rs` exercises generic identity lowering: the constructor moves its
argument into a ManuallyDrop wrapper, so it emits no unwind edge. A conservative
MIR cleanup successor must not introduce an orphan AST block.

`shared_cleanup.rs` checks an ordinary call and a caller sharing cleanup between
ManuallyDrop::new and an ordinary function named `new`. Real unwind paths must
remain reachable. Its `normal_first_cleanup` function is the positive control
for the runtime shape in `shared_false_unwind.rs`.

The false-normal and false-unwind postconditions have one expected-error marker
each and run separately with `-allow_should_fail`. The false-unwind fixture uses
a normal-first tail expression: symbolic execution visits the common return
before the expected unwind error ends verification, and the tail call introduces
no unvisited continuation goto. The unwind contract and real panic path remain.

`dead_code_pre.rs` has a contradictory precondition and must fail the mandatory
dead-code check. The suite uses mysh's existing exact-output assertion to require
the expected dead-code diagnostics and exit status 1. An unrelated early error
cannot satisfy this control. The expected diagnostic is whole-function dead code,
not a failed precondition assertion.
No fixture disables unwind, resource, or dead-code checking.

From this directory after building VeriFast:

```text
verifast forget.rs
verifast shared_cleanup.rs
verifast -allow_should_fail false_normal_post.rs
verifast -allow_should_fail shared_false_unwind.rs
verifast dead_code_pre.rs
```

The last command is expected to exit 1. Run the registered Rust suite from the repository root:

```sh
repo=$(pwd)
(cd tests/rust && PATH="$repo/bin:$PATH" "$repo/bin/mysh" -cpus 1 < testsuite.mysh)
```

Run the full repository suite with `make -C src test` in a configured build
environment.
