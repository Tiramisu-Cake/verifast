# Final ManuallyDrop::new PR review

**READY_FOR_USER_REVIEW**. Complete Linux make test passed in663.71s, exit0,
zero failed processes, on exact final tree. Cloud Build itself is FAILURE because
the outer collector required obsolete `allprooflogs/cases/*`; new source-bound
captures live under `allprooflogs/affected/*`. Raw make/CFG audit succeeded; original
archive/status remain immutable and supplemental collector replay is identified
separately. See CHECKS.md and COLLECTOR-REPLAY.json. No upstream publication is authorized: no PR/draft, public fork, PR branch,
issue, comment or maintainer message. Separate review and explicit user approve
must cover the exact final head and PR body/title hashes; material changes renew
review. GitHub authentication is not publication permission.

The original implementation was developed in proof commit
`e6c02f22420ba4ff6a77e39c9610708a6096e7d7`, used experimentally before maintainer
work, and transferred unchanged at `227dc163117e85d89fb1877bfc1e239a0628e5ab`.
Maintainer review and8f0b701e tests did not invent a new translator repair.
Separate-distribution NOT_ACCEPTED does not erase earlier use or require proof
agents to reaccept unchanged implementation. Actual generic mem::forget/caller
resource proofs remain separately owned.

The previous head da4beb61 remains intact. The final branch is a separate local
clone, /root/verifast-mdnew-final, on current master0a83dba4 selected at session
start. Both PR commits use user-provided Tiramisu-Cake <igkharin@gmail.com> as
author/committer, configured locally in this clone only. Upstream and published
research history were preserved. No global/shared proof-repository identity change.
Translator and five .rs fixtures are unchanged. New base changes Rust launcher
and refiner lookup, so the combined tree receives fresh source-component builds
and full make execution, rather than credit from a clean static merge.

The small new registration uses the exact-output syntax already in upstream
testsuite.mysh:483–484, appends EXIT:1, and explicitly captures child stderr.
It is intentionally coupled to four expected dead-code locations in this fixed
fixture; no framework or disabled checker was introduced. README documents it.
The normal-first tail expression fixes traversal order after an expected unwind
error without weakening that postcondition; its positive mirror remains.

Reviewer questions:

1. Does the marker only remove successors absent from the identity CFG, preserving
   argument evaluation and ordinary/shared cleanup unwind?
2. Are exact diagnostics plus exit1 a suitable native regression for this fixture?
3. Do the new-base compiler/component receipts and affected captures support the
   claimed checks, with conditional skips kept separate?
4. Review the exact head, title/body and public attribution before approve.

Known boundaries: trusted identity/name-specialization representation, refiner
unwind TODO, no general soundness/consumer qualification/upstream acceptance.
Other platforms are outside this session. No legal agreement is signed on the
user's behalf. A previously reported account flag may affect a future submission;
no trial publication was used to probe or bypass it.
