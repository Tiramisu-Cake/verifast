# Checks — exact new head, CI SUCCESS

Head `ac6a63d5cad3a028e5d6f7ee4439169ba443468b`; base `0a83dba42db7ce0b445034ece5298afe980e57dc`; tree `9f3ffe26fc1439460afb1d2bbcb26f283f46276e`. Fork `Tiramisu-Cake/verifast`, branch `fix/manuallydrop-new-cfg-windows-20261020`, verified independently by Git ls-remote and GitHub refs API. Existing workflow build.yml blob `7554f15b073873fcbf154e7ea88a8cc4c42cd609` unchanged.

[Run39339228464](https://github.com/Tiramisu-Cake/verifast/actions/runs/39339228464), event push, attempt1, SUCCESS, `2026-10-19T23:04:20Z`–`2026-10-19T23:15:44Z`. Wall **684s**, sum of applicable job intervals **2048s**; these are Actions durations, not GCP/CPU charges.

| Applicable job | Exact job/check | Result | Elapsed s |
| --- | --- | --- | ---: |
| `build_ubuntu` | [118356330228](https://github.com/Tiramisu-Cake/verifast/actions/runs/39339228464/job/118356330228) | SUCCESS | 391 |
| `check_aarch64_linux_stopwatch` | [118356330545](https://github.com/Tiramisu-Cake/verifast/actions/runs/39339228464/job/118356330545) | SUCCESS | 18 |
| `build_windows` | [118356330589](https://github.com/Tiramisu-Cake/verifast/actions/runs/39339228464/job/118356330589) | SUCCESS | 679 |
| `build_ubuntu_24` | [118356330598](https://github.com/Tiramisu-Cake/verifast/actions/runs/39339228464/job/118356330598) | SUCCESS | 300 |
| `flake-check` | [118356330725](https://github.com/Tiramisu-Cake/verifast/actions/runs/39339228464/job/118356330725) | SUCCESS | 344 |
| `build_macos_aarch` | [118356330764](https://github.com/Tiramisu-Cake/verifast/actions/runs/39339228464/job/118356330764) | SUCCESS | 316 |

Six skipped jobs: upload_ubuntu, upload_ubuntu_release_asset, upload_macos_aarch, upload_macos_aarch_release_asset, upload_windows, upload_windows_release_asset. Ordinary upload conditions require the official repo and master/tag push; release assets require release.created. All are false here. No applicable test job was skipped; Pages did not run.

Build chain at pinned source: build.sh → make nightly → release → release_core (build-cxx-ast-exporter, test, build); Windows invokes make nightly directly. Ubuntu24 additionally requests rocq_metatheory_proofs. This records job/step acceptance, not separate execution counts for each normally conditional internal case (e.g. Java-server/assignments).

[Compact Actions/check/job/step evidence](../../windows-ci-20261020/ACTIONS-SUMMARY.json); all12 check IDs/conclusions match their jobs on the exact new SHA. Full logs/archives were not read; only the explicitly authorized bounded excerpt of the old failed Windows job was retrieved.

[Independent incremental review](../../windows-ci-20261020/INDEPENDENT-REVIEW.md) APPROVE. [Synthetic service checks](../../windows-ci-20261020/SYNTHETIC-CHECKS.json):10PASS (exact stdout/stderr exit1 accepted; exit0/2/127, missing/extra/wrong-location diagnostics and unrelated early error rejected); sh -n PASS. These used an isolated stub as the sole PATH and did not run a real compiler/verifier. [Patch validation](../../windows-ci-20261020/PACKAGE-VALIDATION.json): exact base + pr.diff in a temporary Git index produces the final tree; real worktree/index unchanged.

Historical bf63 run39335742193:5PASS/Windows FAIL. [Addressed audit and root cause](../../windows-ci-20261020/DIAGNOSIS.md): all expected diagnostics but missing EXIT marker under native mysh/cmd.exe; corrected by explicit sh capture. Original Cloud e7724679 Linux-suite PASS/external packaging FAILURE and supplemental replay remain scoped to bf63/old receipts and are not promoted to new-head evidence. No rerun of the old run, baseline build or helper workflow was needed.

Limits: actual local compilation/proof NOT_RUN. This is regression readiness for a narrow existing identity/CFG repair, not independent SmallSort proof credit, consumer pin acceptance, general verifier soundness or upstream acceptance. Existing constructor-name/identity trust boundary and refiner unwind TODO remain unchanged.
