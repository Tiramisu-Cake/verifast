# False-unwind fixture correction

Initial test-only commit fc03ad9e5ab3404398404f3bba9d7bcacec01c43, parent
1435539475fdaa7810bc2bc780fba0514f765f48. The translator Git blob remains
03e7e4079fa3424d1be80a4d0b5d620b899a937f, SHA256
a15a743c4106891e2fde892e26dd3ab2ab87adca04c12b333e6000c4c063509f.
Translator transplant 227dc163117e85d89fb1877bfc1e239a0628e5ab and its prior
independent review are unchanged. New fixture review is separate from that review.

Historical Build 91e5ba26-9a4e-44e0-8bf3-92dc1e4455bd diagnostic copy rejects
`on_unwind_ens false` at shared_false_unwind.rs:14. Its original allow run reaches
that same false condition, consumes the should_fail directive, and then reports
unmarked closing-brace dead code at line18. See the previous immutable packet
50830c7c9f098d8d65df5592dc5e03219d657b89/a87bfb4f for those exact bytes/logs.

`src/verifast1.ml::check_should_fail` (787–798 at the tool pin) catches the
expected error and returns the default from the protected verification scope;
verification does not resume at the next statement. `src/vfconsole/vfconsole.ml`
(267–282,341) independently reports registered but unexecuted statement locations.
The shared normal return's closing-brace location was not visited before the
unwind false post aborted this scope. This is expected-failure traversal in an
ill-shaped test, not evidence of a new translator defect. The harness faithfully
reported both errors; its previous capture-log defect is a separate issue.

The fix supplies a normal-first Boolean branch after ManuallyDrop has consumed
`t`: b=true reaches the common return; b=false calls `new(true)`, whose actual
body panics. The false unwind post and its sole should_fail marker stay unchanged.
There are no assumptions, dead-code directives, extra should_fail markers, or
weakened resources/posts. The corresponding `normal_first_cleanup` positive
control uses the same runtime body and truthful thread-token normal/unwind posts.
Unused expected-error markers still reject disappearance of the target error.

Independent built-in explorer review (GPT-6 Sol) confirmed these source facts,
unchanged translator/testsuite bytes and a real panic input. This is source
review, not execution credit. Cloud must confirm branch order in the exact
function's MIR/AST, the real unwind edge, complete positive/negative logs, and
absence of unexplained dead code. The ordinary and shared-cleanup structural
gates remain mandatory; refiner unwind TODOs are not discharged by exit0.

## Fresh Cloud follow-up

Build 28c02b79-8834-46e4-9f24-c3b1282476b0 at infra/source
f30a7f07ccb45ee4a6266048a4ea15419e2601c5 produced complete captures for fc03ad9.
The shared normal ReturnStmt was visited, but an else-only normal-continuation
GotoStmt at the if-span remained unvisited after the expected unwind failure.
This rules out the closing brace as the remaining location. The captured caller
AST has separate label4-to5 and label2-to5 gotos; only the bypass goto executes.
The ordinary call's trusted summary permits both outcomes; constant `true`
alone is not an established explanation for the traversal ordering.

Follow-up test-only commit 8f0b701e9f2a3da124372c5d37d4cda408d45001 removes the
semicolon in the call arm, making the if a tail expression in both negative and
positive controls. Runtime paths/posts are unchanged, while the call's normal
result can feed the common return directly. Build 8dd10da5-8a6b-40d7-88e2-7f4271324f17 at infra/source cf938bb31348c598de3d261f4169fa13a4bd11ab
attests the final MIR/AST and original fixture success on both sides. Exact
function MIR has normal bb4 as direct Return and cleanup bb5 as UnwindResume;
its AST keeps the ordinary call unwind arm to5 and reachable unwind Return.
The extra normal goto is absent. Positive mirror completes both resource posts;
diagnostic rejects on_unwind_ens false at14, originals exit0 without dead code.
Independent fresh function-scoped evidence review confirms these facts.
Translator remains identical. All focused gates PASS; historical data alone
was not used as execution credit.
