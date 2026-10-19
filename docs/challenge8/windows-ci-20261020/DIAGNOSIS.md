# Windows CI repair — evidence and hypothesis

Session T0 2026-10-19T22:56:23Z; main cutoff 2026-10-20T00:56:23Z; absolute cutoff01:26:23Z. Owner verifast. Docs source755f06bd8f2d9948b217c95f8b42b6e0d1eefd22; technical original bf63b7dff2e053eea8541996d856fac4be11f6f1, base0a83dba42db7ce0b445034ece5298afe980e57dc, tree687ae7dab447c94c4b87362d3d880d959c89e3de preserved. Current own technical branch fix/manuallydrop-new-cfg-windows-20261020.

## Addressed audit

Run39335742193/job118344682458/attempt1/repository Tiramisu-Cake/verifast/headbf63 and job name/status were checked through API before log retrieval. Workflow build.yml blob7554f15b073873fcbf154e7ea88a8cc4c42cd609; Windows step4 Build. API302 followed only in memory; signed URL/credentials not recorded. HEAD confirms plaintext377256bytes and Accept-Ranges bytes. Two bounded GETs of the same final12000bytes, Range365256–377255, returned206 with matching Content-Range and Content-Length, checked **before body read**. A synthetic guard test rejected200/wrong-range/wrong-length responses; redaction tests covered credential-like strings and signed URL queries. No full log/run archive downloaded, no hosted diagnostic helper needed. A first irrelevant cleanup excerpt was discarded; [selected first failure](windows-first-error-excerpt.txt), [coordinates and coverage](windows-first-error-receipt.json). Coverage is the selected tail only, not all earlier expected-negative diagnostics.

## First substantive observation

The only reported failed process is the new dead_code_pre.rs exact-output assertion in tests/rust/testsuite.mysh. Its actual output contains `(type)` and **all four exact dead-code diagnostics, in the expected order and path spelling**. The expected synthetic `EXIT:1` line is absent. The tail reports one failed process, then GNUmakefile589/testsuite error. This is a regression-registration/shell compatibility failure; it does not establish a ManuallyDrop translator error or temporary infrastructure failure. CRLF/order/path mismatches are not observed in this excerpt.

Source trace confirms `src/mysh/mysh.ml:436–447` strips the comparison wrapper and sends its inner command to `Unix.open_process_in`; `:494–502` compares output text in this mode without checking child status. [OCaml4.13 Unix API](https://ocaml.org/manual/4.13/api/Unix.html#VALopen_process_in) documents `/bin/sh` on Unix and `cmd.exe` on Windows. The outer Cygwin Bash does not choose native OCaml's process shell. Thus POSIX-only `; case_exit=$?; echo EXIT:$case_exit` is not interpreted as intended on Windows, explaining the absent status sentinel despite matching diagnostics. Merely removing EXIT:1 or adding `!` would lose exact status checking (mysh output mode ignores exit status; `!` negates the text comparison).

**Implementation rationale before edits:** move only this small capture/exit-reporting sequence into a POSIX `.sh` fixture helper and assert the helper's output via explicit `sh dead_code_pre.sh`. Cygwin's existing shell is already a Windows build prerequisite; this adds no new package/toolchain. The native process shell now sees a plain interpreter/file command, and POSIX status syntax executes inside explicit sh on every platform. Preserve the exact existing expected bytes, including all four diagnostics and EXIT:1; keep the four other commands and all translator/Rust fixture bytes unchanged. README documents why explicit sh is required. No general mysh/diagnostic renderer or workflow/dependency change. No baseline build is currently justified: the failure is the added registration itself, and the mandatory checker reached all expected locations.

## Required invariants and distinguishing controls

The translator and five Rust fixtures retain their existing resource/normal/unwind/constructor-identity/dead-code semantics. Never allow arbitrary nonzero, skip the negative, remove a diagnostic or suppress dead-code checks. The replacement must accept only exact stdout/stderr text plus exit1; synthetic wrong status0/2, missing/extra/wrong-location diagnostic, and unexpected setup error must remain rejected. Four existing positive/false-post/unwind controls stay registered. Actual compiler/tool execution is Actions only; VPS permits source/static and small synthetic parser/classifier checks. A new candidate gets independent Luna HIGH review and the complete existing CI matrix on its exact final SHA.

## Independent review and baseline evidence

[Incremental Luna HIGH review](INDEPENDENT-REVIEW.md): APPROVE with three exact blob fingerprints, checked before submit; no semantic/model change. [Synthetic checks](SYNTHETIC-CHECKS.json): 10PASS, syntax PASS, original expected-output bytes/semantic inputs unchanged. Actual execution remains CI-only.

Read-only upstream base check-runs API reports successful Windows `build_windows` job113970742852 in [existing official run37974941893](https://github.com/verifast/verifast/actions/runs/37974941893), exact base0a83dba42db7ce0b445034ece5298afe980e57dc. This is source-reported historical CI, not our new baseline/proof credit. No upstream CI was launched and no controlled fork baseline was needed for the already isolated added-registration defect.

## Final regression readiness

Exact new head `ac6a63d5cad3a028e5d6f7ee4439169ba443468b` passed [fresh CI39339228464](https://github.com/Tiramisu-Cake/verifast/actions/runs/39339228464), attempt1: six applicable jobs SUCCESS, six release/upload skips, wall684s/sum job intervals2048s. Windows Build and following artifact steps succeeded. No retry, extra baseline, helper workflow or additional technical edit was needed. [New review package](../reviews/manuallydrop-new-windows-20261020/REVIEW.md) pins head/tree/body/checks separately from the untouched bf63 approval snapshot.
