# ManuallyDrop::new upstream preparation

**CHANGES_REQUIRED**: the proposed code/body/bundle are concrete and reviewable,
but mandatory Linux make test stopped at its650s cap during the root suite.
Native registration and full Rust suite passed in both new Builds. The remaining
check is a preparation blocker, not an established candidate defect. Do not
submit this PR until the required suite completes and review/approve is renewed.

This packet proposes a two-commit standalone VeriFast PR, pending independent
review and explicit user approve. It authorizes no upstream publication. Review
must cover the exact head commit and final PR body hash recorded in manifest;
material changes require renewed review.

The original implementation was developed by the proof agent in
`e6c02f22420ba4ff6a77e39c9610708a6096e7d7`, used in an experimental proof profile,
and exercised by historical O1 evidence before the VeriFast maintainer role.
The maintainer transplanted it unchanged at `227dc163117e85d89fb1877bfc1e239a0628e5ab`,
performed independent review and strengthened tests. The validated pin
`8f0b701e9f2a3da124372c5d37d4cda408d45001` is a tool/test packaging identity,
not a new semantic translator fix. Prior `consumer acceptance NOT_ACCEPTED`
described the separate new distribution, not absence of prior experimental use.
No proof agent must reaccept the unchanged implementation to prepare this PR.
Actual generic mem::forget proofs and caller resource obligations remain separate
proof work; they are not an automatic prerequisite for this standalone repair.

The affected successor inventory advertises a MIR cleanup although the existing
identity lowering emits only an assignment/normal goto. The patch removes this
extra target only for the exact recognized ManuallyDrop constructor and only for
FnCallResult with a normal GotoTerminator. Real FnCallOutcome unwind arms, earlier
argument evaluation, shared cleanup and ordinary calls remain. No spec, kernel,
ownership interpretation or refiner change is included.

The tested base remains f76012fb518703b1d98e243ac4f487f16877cfcb. Upstream was
identical at the initial read, but advanced during this session to
0a83dba42db7ce0b445034ece5298afe980e57dc (#1039, Nix/build setup). Translator and
our tests do not overlap its changes; the baseline defect remains in that same
translator and merge-tree is conflict-free. The proposed head stays frozen on
f760. The prospective merge tree70478c6077d3b9d241ce7e49b8666742a227fd13 is NOT_RUN:
new master changes Rust frontend/refiner toolchain lookup. Old-head evidence is
not execution of this combined source profile. Fresh merged-profile CI is needed
before merge acceptance. See UPSTREAM.json and UPSTREAM-ADVANCE.json. No equivalent
successor fix was found.

The clean local branch is upstream/manuallydrop-new-successors at
/root/verifast-mdnew-pr. Full base-to-head diff includes exactly one translator
file, five .rs fixtures, their README and tests/rust/testsuite.mysh. No budgets,
agent reports, proof profiles, infrastructure or evidence are in that branch.
Translator and all .rs bytes equal validated8f0b701e. Changes versus that pin are
history consolidation, README cleanup and one ! dead-code registration. No base,
implementation or fixture-byte change. Prior execution applies by equality of
all significant source/spec/toolchain inputs, not by an invented run at new SHA.
Fresh native registration execution is recorded separately in CHECKS.md.

Reviewer questions:

1. Does the narrow constructor marker remove only the orphan bookkeeping target
   and preserve all genuinely emitted unwind edges and shared cleanup?
2. Does normal-first tail expression preserve the false unwind contract, with
   the positive mirror and unused-marker rejection preventing vacuous success?
3. Is native `! verifast dead_code_pre.rs` acceptable as the usual nonzero-exit
   smoke control? Fresh audit checks the exact dead-code error; native ! itself
   cannot distinguish an unrelated early failure.
4. Approve the visible Git metadata or provide a verified replacement identity:
   both commits record root <root@03ohba7t.vm>. The implementation author/date
   are preserved from the original proof commit; no human identity is invented.
5. Confirm the final head, title and PR-BODY.md digest before any upstream action.

Known limits: existing identity lowering and name-specialization resolution remain
trusted; no raw-DefId hardening. Refiner unwind TODO is not discharged. Focused
PASS is not general VeriFast soundness, consumer proof qualification or upstream
acceptance. Broader CI/platform checks and any remaining suite blockers are explicit
in CHECKS.md. No committed CLA/DCO or personal-signature requirement was found;
no legal agreement was accepted. A previously reported GitHub account flag may
still prevent future public submission; no trial fork/PR/comment was used to test
or bypass it.

Public information proposed upstream: source/test code, README and reproduction
commands, title/body, root author/committer names and VM email, commit timestamps,
original proof-repo name and original/transplant commit IDs. Exact evidence links
in the final body are listed separately in PUBLICATION-INSTRUCTIONS.md. Old Cloud
archives are referenced by immutable links/hashes and are not recopied here.
