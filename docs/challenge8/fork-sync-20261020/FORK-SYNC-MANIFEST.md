# FORK-SYNC-MANIFEST — 2026-10-20

Task `verifast-fork-sync-2026-10-20-r1`; owner `verifast`.

T0 **2026-10-19 22:25:31 UTC** (2026-10-20 01:25:31 MSK); main cutoff 2026-10-20 00:25:31 UTC; absolute cutoff 00:55:31 UTC. GCP budget/builds **0**. Existing fork Actions CI authorized; no upstream PR, release, message or consumer acceptance authorized.

## Sources and preservation boundary

Read own AGENTS/CURRENT-TASK/WORKFLOW/STATUS and approval REVIEW at `d17abbeb1d56e646743536aae998b104dbdc4181`. Compared newer docs HEAD against `d426323cc8824bf85af3cc0a2c7eda03daf7a44c`: only AGENTS, CURRENT-TASK, WORKFLOW and archived prior task changed in `82037e76`/`d17abbeb`. No rollback. Proof-policy source is read-only exact `b1b12502c3a920ef16f51d2a36280cc41f8b74e6` in `/root/verify-rust-std-evidence-brief` (AGENTS, WORK-POLICY, COMPLETION-PLAN, role, iteration policy and coordinator description); historical executed source `66ef5f0eac2c72f2366f4a1c8900291a0c20940d` remains a historical binding. Upstream README.txt, src/README.txt and README.Linux.md read. No new proof obligation/model design.

Metadata snapshots are private local recovery data under `/root/verifast-fork-sync-recovery/20261019T222531Z`: `inventory.before.json`, per-repository `refs.before.tsv`, `remotes.before.txt`, `config.before`, `worktrees.before.txt`. Git status used `--no-optional-locks`; no foreign index refresh/write. Own five trees were entirely clean, including untracked files: ten empty binary worktree/index diffs saved, SHA256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`; no own untracked source needed copying. Other dirty files stay in their original trees. Archive evidence: only presence/stat metadata inspected (`archive-metadata.before.json`); contents were not opened.

## Initial worktrees

All paths below share `/root/verifast/.git`, except `/root/verifast-mdnew-final`, whose independent common-dir is `/root/verifast-mdnew-final/.git`. Full initial HEAD/tree and dirty status are captured below. Dirty counts are porcelain records (metadata, not proof results).

| Worktree | Initial branch / detached | HEAD | Tree | Owner / purpose | Dirty records | Action |
| --- | --- | --- | --- | --- | ---: | --- |
| `/root/verifast` | `infra/maintainer-coordinator-v3-20261012` | `d17abbeb1d56e646743536aae998b104dbdc4181` | `2dfcabd765af17036b89d43b1949793f71eb7442` | verifast; organizational; original docs checkpoint | 0 | docs canonical alias; old ref preserved |
| `/root/verifast-i-actual-glue` | `candidate/i-actual-glue-prereqs-20261012` | `c23278c3ea716b64d2fdeee134b834095956ac56` | `3a2c16640c10958a5d185dc8d928c47950406907` | UNKNOWN; not assigned to maintainer | 0 | untouched |
| `/root/verifast-maintainer-c4-composition-20261010b` | `research/maintainer-c4-composition-20261011c` | `4a34010cc3930eec46fc4e72c1b793ad734fa730` | `df5731894e7850d95c95338ee8c5f81ad335c3aa` | UNKNOWN; not assigned to maintainer | 0 | untouched |
| `/root/verifast-maintainer-native-h` | `candidate/native-zst-c3-20261011` | `46181aff379a5d4231cc51814cfe3732bda21c03` | `94e14201602b0bab96caade9f7a2bfee5459480e` | UNKNOWN; not assigned to maintainer | 0 | untouched |
| `/root/verifast-maintainer-slice-i` | `candidate/slice-as-mut-ptr-native-c3-20261011` | `b6cb276afd13107c2a90ca50acbb12ff0a992dd8` | `46bcfea2babd5233b82b6dd63db9fffccb615b4d` | UNKNOWN; not assigned to maintainer | 0 | untouched |
| `/root/verifast-manuallydrop-review` | `challenge8/manuallydrop-new-cfg-review` | `9209cc9dfdf9f70df5a2ee9b790dc7a66caf5cca` | `be55d8d934fb10617309a289e0d546ca1aed6ea0` | verifast; validation/review history | 0 | untouched |
| `/root/verifast-mdnew-pr` | `upstream/manuallydrop-new-successors` | `da4beb61a6c2dd0e80fe4a74c5c230f3adac7cab` | `50481095a79cb8f517fb61c0a4aa5d026b591b91` | verifast; validation/review history; superseded candidate | 0 | untouched |
| `/root/verifast-mdnew-validation` | `challenge8/mdnew-focused-validation` | `8f0b701e9f2a3da124372c5d37d4cda408d45001` | `de79cb7af14ebf1d60cc11f00eeb9940f003951d` | verifast; validation/review history | 0 | untouched |
| `/root/verifast-merge-actual-glue` | `merge/actual-glue-instance-20261011` | `a42d50becbc84a45e33a58269358eee105f1fdcb` | `615ed50edfa8edf5b5ebf02c8d739cf9342c8bc6` | Merge; active per task | 0 | untouched |
| `/root/verifast-merge-allocation-span` | `merge/allocation-span-20261009` | `8c1386a802ba2ff43ffdd6787eaef5e47bf068e1` | `b09af039144311843006ddd8e64f98c1c65bf929` | UNKNOWN; not assigned to maintainer | 0 | untouched |
| `/root/verifast-merge-incoming-span` | `merge/incoming-span-lifetime-20261009` | `df6b3fbfcf4192d6b442d13e35dafe8477a3fe6f` | `00e9c7f7e58e179eca105b79542508551c6a5532` | UNKNOWN; not assigned to maintainer | 0 | untouched |
| `/root/verifast-merge-selected-drop` | `merge/selected-drop-receiver-20261011` | `8a3f63eabf18cc76cc9048c086dda95fbec84d03` | `41dfdbb8f7cb811ca69f5d6f4908d682ceaa179c` | UNKNOWN; not assigned to maintainer | 0 | untouched |
| `/root/verifast-select-compatible-strict-cut-20261010` | `DETACHED` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; not assigned to maintainer | 2 | untouched |
| `/root/verifast-select-native-c1-bound-20261010` | `DETACHED` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; not assigned to maintainer | 2907 | untouched |
| `/root/verifast-select-native-compose-20261010` | `DETACHED` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; not assigned to maintainer | 3 | untouched |
| `/root/verifast-select-sort4-c2-bind-20261010` | `challenge8/select-sort4-c2-bound-20261010` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; not assigned to maintainer | 4 | untouched |
| `/root/verifast-select-sort4-c3-bind-20261010` | `DETACHED` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; not assigned to maintainer | 4 | untouched |
| `/root/verifast-select-sort4-c4-bind-20261010` | `DETACHED` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; not assigned to maintainer | 4 | untouched |
| `/root/verifast-select-sort4-native-20261010` | `DETACHED` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; not assigned to maintainer | 4 | untouched |
| `/root/verifast-select-sort4-opaque-20261010` | `research/sort4-native-opaque-binding-2026-10-10` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; not assigned to maintainer | 2906 | untouched |
| `/root/verifast-slice-upstream-l` | `upstream/slice-as-mut-ptr-20261011` | `095ef553e92deaae063b3684ea3172128e666785` | `54e80209593942d1381283f71fa916c02fa4ac57` | UNKNOWN; not assigned to maintainer | 0 | untouched |
| `/tmp/c8-merge-incoming-span-20261009/assembled` | `DETACHED` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; not assigned to maintainer | 4 | untouched |
| `/root/verifast-mdnew-final` | `upstream/manuallydrop-new-final-20261009` | `bf63b7dff2e053eea8541996d856fac4be11f6f1` | `687ae7dab447c94c4b87362d3d880d959c89e3de` | verifast; ready candidate; original final branch | 0 | technical canonical alias; old ref preserved |

## Initial local branches and ownership

Ownership follows explicit current-task assignments and existing ManuallyDrop review/history. The bounded read-only helper found no handoff in local docs/history establishing ownership of the extra native/C4/slice/i branches; author identity or directory prefix alone is insufficient. Such branches remain UNKNOWN and unpublished. Existing tags and all original refs remain unchanged; full tags/remotes/tracking are in the snapshots. No detached commit assigned to maintainer was found.

| Repository | Initial ref | SHA | Tree | Classification / owner | Action |
| --- | --- | --- | --- | --- | --- |
| common | `refs/heads/candidate/i-actual-glue-prereqs-20261012` | `c23278c3ea716b64d2fdeee134b834095956ac56` | `3a2c16640c10958a5d185dc8d928c47950406907` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/candidate/native-zst-c3-20261011` | `46181aff379a5d4231cc51814cfe3732bda21c03` | `94e14201602b0bab96caade9f7a2bfee5459480e` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/candidate/slice-as-mut-ptr-native-c3-20261011` | `b6cb276afd13107c2a90ca50acbb12ff0a992dd8` | `46bcfea2babd5233b82b6dd63db9fffccb615b4d` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/challenge8/manuallydrop-new-cfg-review` | `9209cc9dfdf9f70df5a2ee9b790dc7a66caf5cca` | `be55d8d934fb10617309a289e0d546ca1aed6ea0` | verifast; validation/review history | backup ref + verified bundle; preserve local original |
| common | `refs/heads/challenge8/manuallydrop-new-cfg-upstream-candidate` | `1435539475fdaa7810bc2bc780fba0514f765f48` | `be55d8d934fb10617309a289e0d546ca1aed6ea0` | verifast; inactive legacy candidate | backup ref + verified bundle; preserve local original |
| common | `refs/heads/challenge8/mdnew-focused-validation` | `8f0b701e9f2a3da124372c5d37d4cda408d45001` | `de79cb7af14ebf1d60cc11f00eeb9940f003951d` | verifast; validation/review history | backup ref + verified bundle; preserve local original |
| common | `refs/heads/challenge8/select-sort4-c2-bound-20261010` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/challenge8/verifast-maintainer` | `9d776517d82acca133a05fcac86e70f67f550bb5` | `3ec6668a15db21dbc88e26e9a2e88d2a30b8ae8c` | verifast; organizational; inactive predecessor | backup ref + verified bundle; preserve local original |
| common | `refs/heads/infra/maintainer-coordinator-v3-20261012` | `d17abbeb1d56e646743536aae998b104dbdc4181` | `2dfcabd765af17036b89d43b1949793f71eb7442` | verifast; organizational; original docs checkpoint | backup ref + verified bundle; preserve local original |
| common | `refs/heads/input/manuallydrop-new-final-20261009` | `bf63b7dff2e053eea8541996d856fac4be11f6f1` | `687ae7dab447c94c4b87362d3d880d959c89e3de` | verifast; ready candidate; imported exact final head | backup ref + verified bundle; preserve local original |
| common | `refs/heads/master` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | upstream baseline; inactive alias | preserve local; no publication or branch/tracking change |
| common | `refs/heads/merge/actual-glue-instance-20261011` | `a42d50becbc84a45e33a58269358eee105f1fdcb` | `615ed50edfa8edf5b5ebf02c8d739cf9342c8bc6` | Merge; active per task | preserve local; no publication or branch/tracking change |
| common | `refs/heads/merge/allocation-span-20261009` | `8c1386a802ba2ff43ffdd6787eaef5e47bf068e1` | `b09af039144311843006ddd8e64f98c1c65bf929` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/merge/incoming-span-lifetime-20261009` | `df6b3fbfcf4192d6b442d13e35dafe8477a3fe6f` | `00e9c7f7e58e179eca105b79542508551c6a5532` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/merge/selected-drop-receiver-20261011` | `8a3f63eabf18cc76cc9048c086dda95fbec84d03` | `41dfdbb8f7cb811ca69f5d6f4908d682ceaa179c` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/research/challenge-8` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | upstream baseline; inactive alias | preserve local; no publication or branch/tracking change |
| common | `refs/heads/research/maintainer-c4-composition-20261010b` | `e2e674f8727259ef08c68e58bb5dae1bd723cf76` | `d35d6e79e3ce787d3620468506e28f74abe7b644` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/research/maintainer-c4-composition-20261011c` | `4a34010cc3930eec46fc4e72c1b793ad734fa730` | `df5731894e7850d95c95338ee8c5f81ad335c3aa` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/research/maintainer-c4-selector-20261010` | `423d5e3cb1781ed58f8933146a555470f7b42115` | `5f9182d7df11b6c9754f1a09f52190d45fc74350` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/research/maintainer-port-deps-preserved-20261010b` | `57bdb9ed2fc45a420fb3b3f98ee004f01d709846` | `3f93a4029f8a11869cd781406400c1be187f7617` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/research/sort4-native-opaque-binding-2026-10-10` | `f76012fb518703b1d98e243ac4f487f16877cfcb` | `d7e55e183ecabfdb0a79cfe600fd0f2419124926` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| common | `refs/heads/upstream/manuallydrop-new-successors` | `da4beb61a6c2dd0e80fe4a74c5c230f3adac7cab` | `50481095a79cb8f517fb61c0a4aa5d026b591b91` | verifast; validation/review history; superseded candidate | backup ref + verified bundle; preserve local original |
| common | `refs/heads/upstream/slice-as-mut-ptr-20261011` | `095ef553e92deaae063b3684ea3172128e666785` | `54e80209593942d1381283f71fa916c02fa4ac57` | UNKNOWN; experimental/history by subject only | preserve local; no publication or branch/tracking change |
| final | `refs/heads/challenge8/verifast-maintainer` | `c8dfc5b64b3398ffa17899abb3f4daeed543e715` | `fd3bf7d00aa7765c6f19f5c3b64c366dbc76cc3f` | verifast; organizational; inactive predecessor | backup ref + verified bundle; preserve local original |
| final | `refs/heads/upstream/manuallydrop-new-final-20261009` | `bf63b7dff2e053eea8541996d856fac4be11f6f1` | `687ae7dab447c94c4b87362d3d880d959c89e3de` | verifast; ready candidate; original final branch | backup ref + verified bundle; preserve local original |

## Recovery

Only confirmed own branches received additive refs under `refs/backup/fork-sync-20261020/<original-branch>`. No original refs/tags were deleted, rewritten, garbage-collected or pruned. Both standalone bundles passed `git bundle verify` in the source repository **and an empty independent bare repository**, then explicit fetch and `cat-file -e`/tree equality for every saved head. No source checkout, compiler or verifier was invoked.

| Repository | Bundle | Bytes | SHA256 | Restored heads |
| --- | --- | ---: | --- | ---: |
| `/root/verifast` | `/root/verifast-fork-sync-recovery/20261019T222531Z/common/pre-sync.bundle` | 16159736 | `bee1d6b4ba176fa4301ce03f1fd4ec1c0ec9eec893a73d3a107bece84568c0dc` | 7 |
| `/root/verifast-mdnew-final` | `/root/verifast-fork-sync-recovery/20261019T222531Z/final/pre-sync.bundle` | 16062511 | `6c536452c6ba0363ddef6e0dc853c39cdfd15aded7ad96abed718f7b5996ee1f` | 2 |

Verification receipts, all backup ref mappings and restored commit/tree checks: `/root/verifast-fork-sync-recovery/20261019T222531Z/bundles.json`, per-repository `bundle-verify.txt`/`isolated-bundle-verify.txt`; existing inspection repositories `common/restore.git`, `final/restore.git`.

Recovery in a new location: `git init --bare /chosen/recovery.git`; then `git -C /chosen/recovery.git fetch --no-tags <absolute-bundle-path> refs/backup/fork-sync-20261020/<original-branch>:refs/heads/recovered`. Verify expected SHA/tree against `bundles.json` before using a checkout. Original local remote configuration is in `config.before`; recover selected settings deliberately, never overwrite live shared config. Bundles on this VPS are local recovery, not external backup.

## Remotes, canonical branches and publication

Common repo initially had only `upstream=https://github.com/verifast/verifast.git`; added `origin=https://github.com/Tiramisu-Cake/verifast.git` once for the common-dir. Final clone initially had `origin=/root/verifast`; renamed it to `local-source` (preserving its remote refs/tracking under the renamed namespace), then added fork `origin` and official `upstream`. No global Git configuration/identity changed.

| Work | Old branch / SHA | Canonical branch / SHA | Publication |
| --- | --- | --- | --- |
| docs | `infra/maintainer-coordinator-v3-20261012` / `d17abbeb1d56e646743536aae998b104dbdc4181` | `maintenance/fork-sync-20261020` from that exact HEAD | pending checkpoint |
| candidate | `upstream/manuallydrop-new-final-20261009` / `bf63b7dff2e053eea8541996d856fac4be11f6f1` | `fix/manuallydrop-new-cfg` / same SHA, both repositories | published; Git and API both confirmed exact bf63b7df |

The two confirmed own canonical refs are selected for publication; an additional exact-head CI alias is documented below. The technical history preserves its review predecessors; the docs branch carries the existing review/evidence bindings without publishing raw archive files separately. Legacy validation refs stay local and are superseded by final bf63b7df. UNKNOWN and active foreign experimental refs are not published. No branch-name conflict existed. Master/tags/releases remain untouched.

## Candidate and review invariants

Base `0a83dba42db7ce0b445034ece5298afe980e57dc`; head `bf63b7dff2e053eea8541996d856fac4be11f6f1`; tree `687ae7dab447c94c4b87362d3d880d959c89e3de`. No rebase/amend/cherry-pick/merge, code/test/registration/workflow edits. Exactly eight candidate files differ from base. PR body SHA256 `c1b21d031078e12bfacce8301aee7ec9e9f552e97e4542de2d3cf96c9febb10c`; title SHA256 `dfa9b93e9368fdb751625483adfe217c476152f0fcd53694c3e42807f1c21b1c`: `[Rust] Keep ManuallyDrop::new identity successors consistent with the CFG`. [Immutable approval review](../reviews/manuallydrop-new-approval-20261009/REVIEW.md) is preserved. Existing Cloud e7724679 Linux-suite PASS / external packaging FAILURE and supplemental replay remain historical, unchanged; a new fork run cannot rewrite those receipts or imply consumer acceptance.

## Actions and baseline

Initial GitHub API: fork parent `verifast/verifast`, default `master`, ADMIN; Actions enabled=true, zero registered workflows/runs. Fork master and official upstream master both `0a83dba42db7ce0b445034ece5298afe980e57dc`. Initial local master/upstream tracking `f76012fb518703b1d98e243ac4f487f16877cfcb`. After fetch without prune/tags: local master is 0 ahead/1 behind official upstream; upstream/master versus fork origin/master is 0/0; candidate is 2 ahead/0 behind upstream, merge-base exactly base0a83. Local master was not moved.

Existing `.github/workflows/build.yml` at candidate SHA (name `CI`, push event) is the target. Required jobs: `build_ubuntu`, `build_ubuntu_24` (Rocq mode), `check_aarch64_linux_stopwatch`, `build_macos_aarch`, `build_windows`, `flake-check`. Build chain: `build.sh` → `make nightly` → `release` → `release_core: build-cxx-ast-exporter test build`; Windows invokes make nightly directly. Release/upload-only jobs are inapplicable on a fork branch push. No workflow bytes/triggers/checks will be changed. Compact Actions evidence only; no full logs/downloads.

### Activation and branch deviation

The first canonical branch push happened before fork workflow registration and created **no run**. `PUT actions/workflows/build.yml/enable` initially returned HTTP404. Reasserting repository `actions/permissions` with `enabled=true` registered the existing CI and Pages workflows, both active; `allowed_actions=all` and other permissions remained unchanged. CI ID `389935016` was explicitly enabled. An idempotent, non-forced PATCH of canonical ref to its already-current bf63 SHA returned the same SHA and did not create a run; no ref target moved. Existing workflow has no workflow_dispatch. No deletion, rewind, force push, source/workflow edit or fabricated commit was used.

To obtain useful exact-head CI within the authorized selected-own-refs scope, created and ordinarily pushed **additional** ref `ci/manuallydrop-new-cfg-20261020` at exactly bf63. This produced run [39335742193](https://github.com/Tiramisu-Cake/verifast/actions/runs/39335742193), event push, attempt1, workflow389935016, head bf63b7dff2e053eea8541996d856fac4be11f6f1, started 2026-10-19T22:33:05Z. **This is a deviation from the requested run branch `fix/manuallydrop-new-cfg`: the canonical branch remains published/unchanged, while the run is bound to the CI alias.** Six applicable test jobs have no branch-name conditions; release-upload conditions exclude both fork branches. Exact commit/tree/workflow is identical, but a canonical-branch push-event receipt is still absent; do not report the alias run as a canonical-branch run.

Both canonical technical tracking branches now follow origin/fix/manuallydrop-new-cfg in their respective repositories. CI alias has no new tracking changes. Only confirmed own refs are published. Git and GitHub API independently confirmed the technical canonical SHA; CI alias SHA was also independently confirmed via Git and GitHub API; terminal result pending.

Workflow source revision is exact candidate bf63, blob `7554f15b073873fcbf154e7ea88a8cc4c42cd609` for build.yml; gh-pages blob `787ec827408965bd5f33c91f00da5f4d91cddf60`. Pages only triggers master and did not run. No master/tags push. Background server execution does not extend agent T0.

Preservation check after technical push: all23 initial worktree HEADs unchanged; status bytes identical for the22 worktrees outside the edited docs tree; all79 checked original heads/tags/final-clone remote mappings retained (`preservation-check.json` in private recovery root). UNKNOWN/foreign dirty sources were not read/copied. Final docs checkpoint and terminal compact Actions evidence pending.
