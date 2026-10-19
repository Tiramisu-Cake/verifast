# Fork synchronization — SYNC_DONE / CI_FAILED (2026-10-20)

Current task: [fork sync and exact-head Actions CI](CURRENT-TASK.md).
Fork: [Tiramisu-Cake/verifast](https://github.com/Tiramisu-Cake/verifast), parent
`verifast/verifast`; fork Actions enabled by owner authorization.
Docs checkout `/root/verifast`: `maintenance/fork-sync-20261020` from
`d17abbeb1d56e646743536aae998b104dbdc4181`.
Technical checkout `/root/verifast-mdnew-final`: `fix/manuallydrop-new-cfg`,
unchanged exact head `bf63b7dff2e053eea8541996d856fac4be11f6f1`.
Both repos use fork `origin` and official `upstream`; final clone additionally
preserves `/root/verifast` as `local-source`.
[Manifest and recovery bindings](fork-sync-20261020/FORK-SYNC-MANIFEST.md).
Two verified standalone recovery bundles preserve own original refs; foreign
and UNKNOWN worktrees/dirty source stay untouched. Historical refs retained.
Canonical technical branch published and independently verified by Git/API.
Fork workflow activation required reasserting enabled=true; first push had no run.
[CI run39335742193](https://github.com/Tiramisu-Cake/verifast/actions/runs/39335742193)
completed FAILURE at exact bf63 on additional `ci/manuallydrop-new-cfg-20261020`:
5/6 applicable jobs PASS (Ubuntu22/24 including Rocq, macOS, aarch64, flake-check),
Windows Build FAIL exit1 after setup PASS; root cause UNKNOWN from allowed summaries.
Six release/upload jobs skipped by repository/event guards (Windows also has a
failed dependency). Run wall8m05s; sum of applicable job intervals1774s. No rerun.
[Compact terminal evidence](fork-sync-20261020/ACTIONS-SUMMARY.json).
This alias run differs from the requested canonical branch event; original
canonical ref is preserved. Green readiness is not achieved. Initial docs checkpoint
`0bd1d05bb53cb34811e66838d50690e55ee12a76` published and verified; final report on
this same docs branch (post-push SHA receipt in the recovery directory).
Next: explicitly authorized administrative inspection of this Windows Build
step's first actual error; full logs were not accessed in this session.
GCP budget/builds0; no local compilation/proof, upstream PR or consumer acceptance.
Upstream publication still requires explicit approval of exact head/title/body;
existing authorization covers the selected branches in the user's fork only.

## Historical ManuallyDrop checkpoint (2026-10-09)

The snapshot below is historical. Its former no-fork/local-only wording and
publication wait do not override the current fork-branch/Actions authorization.
Original head, body, reviews and Cloud evidence retain their dated scope.

# ManuallyDrop::new — READY_FOR_USER_APPROVAL

Independent code/original-archive review completed without blockers, as reported
by user. Requested PR testing paragraph now names exact candidate and all normal
Rocq/Java-server/assignments skips; other body/title unchanged. Candidate base
`0a83dba42db7ce0b445034ece5298afe980e57dc`, head `bf63b7dff2e053eea8541996d856fac4be11f6f1`, tree `687ae7dab447c94c4b87362d3d880d959c89e3de`, identity Tiramisu-Cake <igkharin@gmail.com>
and binary diff remain unchanged. No rebase/amend/code/test/registration change.
PR-BODY.md SHA256 `c1b21d031078e12bfacce8301aee7ec9e9f552e97e4542de2d3cf96c9febb10c`; title `[Rust] Keep ManuallyDrop::new identity successors consistent with the CFG`.
[Approval review](reviews/manuallydrop-new-approval-20261009/REVIEW.md),
[exact PR](reviews/manuallydrop-new-approval-20261009/PR-DRAFT.md).
Linux make test PASS; original Build e7724679 external FAILURE from packaging;
collector replay local service only. New task Cloud budget0s, no new phase/build,
compilation or repeated tests. No upstream publication is authorized or performed.
Next: explicit user approve of exact head/title/body; then stop pending that action.

## Historical full Linux checkpoint

# ManuallyDrop::new — final Linux / user review checkpoint

**READY_FOR_USER_REVIEW**. Full Linux make test: **PASS**, 663.71s (11m03.71s), including build prerequisites; Build `e7724679-b9c0-4526-ac63-1e8020b4114f`.
Cloud status FAILURE is an outer collector cases/* mismatch after suite exit0;
original archive/status preserved, supplemental packaging replay48dc passed.
Final base `0a83dba42db7ce0b445034ece5298afe980e57dc`, head `bf63b7dff2e053eea8541996d856fac4be11f6f1`, tree `687ae7dab447c94c4b87362d3d880d959c89e3de`.
Local-only branch `upstream/manuallydrop-new-final-20261009` in /root/verifast-mdnew-final; previous
/root/verifast-mdnew-pr head da4beb61 preserved. No public fork/head branch, PR
(including draft), issues, comments or maintainer messages. Explicit user approve
of this exact head/title/body SHA256 `e49180a8d4afab3e3e504f3f5ab21a5813e1eedcdba1bf4c08b1b65c66366986` is still required after separate review.
GitHub authentication is not authorization.

Both PR commits author/committer Tiramisu-Cake <igkharin@gmail.com>, user-provided
and configured only in the independent own clone; no global or foreign config
changes. Original proof-agent repair e6c02f22420ba4ff6a77e39c9610708a6096e7d7
was used experimentally before maintainer work. Transfer227dc163 unchanged;
review/stronger8f0b tests are separate packaging, not a new translator fix.
No proof-agent reacceptance is required for unchanged implementation; actual
mem::forget/caller proof obligations remain separately owned.

Translator and five .rs bytes unchanged from validated8f0b/previous da4 head.
New base0a83 changed toolchain lookup and CXX build; new full suite and source-built
component identities are tied to final tree/compiler, rather than old static merge.
Registration now uses upstream mysh exact-output form plus EXIT1 and explicit
stderr, rejecting arbitrary early nonzero errors. README and metadata updated;
only8 submission files, no Cloud/proof/organizational files in PR branch.

Historical focused8dd10da5/targeted38b9ad73 evidence retains its input-bound scope;
new-base affected checks/conditional skips are in CHECKS.md. Other platforms
NOT_RUN. Existing trusted identity/name resolution and refiner unwind TODO remain;
no general soundness, consumer qualification or upstream acceptance claimed.

New own phase CLOSED: 950/3600s; remaining
2650 is historical, not transferred. All own
submissions terminal/accounted/download-verified, active/unresolved/reservations0.
Coordinator v2/max2 preserved; no migration or foreign ledgers/pins/worktrees edits.
Executed infra/source66ef5f0eac2c72f2366f4a1c8900291a0c20940d; organization
checkpoint edc99fb089e91bec2a5cce7fd27d6a66899f1d67 is distinct. Session20:21:27–21:21:27UTC,
finish-only21:51:27UTC; no new Build after main cutoff.

[Review](reviews/manuallydrop-new-fullmake-20261009/REVIEW.md),
[exact PR](reviews/manuallydrop-new-fullmake-20261009/PR-DRAFT.md),
[checks](reviews/manuallydrop-new-fullmake-20261009/CHECKS.md).
Next: independent/user review of exact head/body/title; wait for explicit approve
before any upstream publication.
