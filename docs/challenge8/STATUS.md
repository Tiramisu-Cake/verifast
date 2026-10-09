# Checkpoint: ManuallyDrop::new focused validation

2026-10-09. **FOCUSED_VALIDATION_PASS**. Exact source-built baseline reproduces the orphan cleanup dead-code defect; candidate passes generic forget and retains ordinary/shared unwind. All mandatory focused gates passed, including exact false-post diagnostics, original should_fail fixtures and mandatory dead-code control. Five targeted native upstream regressions passed. Delivery and compilation PASS; full upstream suite and consumer integration NOT_RUN; consumer/upstream acceptance NOT_ACCEPTED.

Tool/test pin8f0b701e9f2a3da124372c5d37d4cda408d45001, basef76012fb518703b1d98e243ac4f487f16877cfcb; translator227dc163117e85d89fb1877bfc1e239a0628e5ab unchanged. Test-only fc03ad9e5ab3404398404f3bba9d7bcacec01c43 and8f0b701 repair expected-failure traversal using a normal-first tail expression and matching positive control. Focused infra=sourcecf938bb31348c598de3d261f4169fa13a4bd11ab includes the capture-log correction; regression infra=source09f8fea4ab3ad987c66e68cd6e7405c9de278161 fixes case-evidence packaging.

Builds:28c02b79-8834-46e4-9f24-c3b1282476b0 FAILURE346s (diagnostic fixture attempt),8dd10da5-8a6b-40d7-88e2-7f4271324f17 SUCCESS351s (focused),b5c898e4-4049-4770-9d73-424703c8168c FAILURE372s (packaging),38b9ad73-55de-452e-9213-bbe4be886562 SUCCESS353s (upstream targeted). New independent phase CLOSED **1422/3600s**, remaining2178; all terminal/accounted/download-verified, own reservations/unresolved0. Historical phase CLOSED786/3600 and2814 remainder unchanged and not inherited.

Actual session16:56:51UTC, main17:56:51UTC, absolute18:26:51UTC. Live coordinatorv2/max2; client ACKs absent and three-slot migration NOT_RUN. Exact peer adoption instructions and gates are in [current session record](cloud/verifast-mdnew-validation-20261009.md).

Sole active owner of this review/test variant: maintainer at /root/verifast-mdnew-validation, branch challenge8/mdnew-focused-validation. Previous review worktree remains preserved as historical source. Proof agents retain their experimental profiles; no proof branches/files/indexes/pins or ledgers changed. Own infra branch infra/verifast-mdnew-cfg and immutable review/verifast package are published; exact organizational checkpoint and publication hashes are separate manifest fields. Prior checkpoint a87bfb4f6e9f45cf221b6f4b7c58315a0fb00f47 / publication50830c7c9f098d8d65df5592dc5e03219d657b89 preserved.

[Fresh fixture/evidence review](reviews/manuallydrop-new-focused-20261009/FIXTURE-REVIEW.md), [updated PR draft](reviews/manuallydrop-new-cfg-20261009/PR-DRAFT.md), [historical session](cloud/verifast-mdnew-20261009.md). Upstream PR/issues remain unpublished. Focused PASS qualifies this bounded test result, not a consumer proof profile or upstream acceptance. Refiner unwind correspondence TODO remains.

Next assignment: Consumer owner: frozen 8f0b701e tool/test bundle against actual generic mem::forget helper and ordinary/shared cleanup callers, with source/spec profile and ownership resources explicitly checked; new authorized Cloud phase, no automatic proof pin adoption.

Organizational infrastructure checkpoint: bc8e9b41baab5bfa39bac81f30b74f9878c6b565. Executed infra/source pins above are distinct from this documentation/accounting commit.
