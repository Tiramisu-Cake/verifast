# READY_FOR_USER_REVIEW — new exact head, CI green

Head `ac6a63d5cad3a028e5d6f7ee4439169ba443468b`; base `0a83dba42db7ce0b445034ece5298afe980e57dc`; tree `9f3ffe26fc1439460afb1d2bbcb26f283f46276e`.
Head repository [Tiramisu-Cake/verifast](https://github.com/Tiramisu-Cake/verifast), branch `fix/manuallydrop-new-cfg-windows-20261020`; sole active maintainer submission variant in `/root/verifast-mdnew-final`. Full remote SHA verified by Git and API. Original bf63 refs/history and approved snapshot remain unchanged.

The original translator and all five Rust fixture bytes are unchanged from bf63. The three-file incremental fix moves only POSIX status capture into an explicit sh fixture helper; registration retains exact diagnostic text/order and EXIT:1; README explains the native Windows child-shell boundary. No mysh/kernel/model, workflow, build/dependency, source guarantee or test-skip change. [Independent Luna HIGH review](../../windows-ci-20261020/INDEPENDENT-REVIEW.md) approved exact three-file blobs before submit; 10 synthetic controls PASS.

[Fresh full CI](CHECKS.md): 6/6 applicable jobs SUCCESS on this exact new SHA, six release/upload-only jobs skipped, attempt1, no reruns. [Rationale/audit](../../windows-ci-20261020/DIAGNOSIS.md), [diff](pr.diff), [exact proposed PR](PR-DRAFT.md). Original proof-agent attribution is preserved byte-for-byte in ORIGINAL-ATTRIBUTION.json; new capture helper is maintainer regression packaging, not a new semantic repair.

PR body SHA256 `f16f05bc8802c9e97aa9f01b77b3a807e897a5488f6a557ed3e6a6ce3aff427f`; title SHA256 `dfa9b93e9368fdb751625483adfe217c476152f0fcd53694c3e42807f1c21b1c`; full diff SHA256 `38f75b7ec8919041cc0c7e35eda117bfc023d00fe955f71462703c81754f80af`. Title: [Rust] Keep ManuallyDrop::new identity successors consistent with the CFG.

**Fresh user review/approval must cover this exact head/title/body before upstream publication.** Old body SHA c1b21d031078e12bfacce8301aee7ec9e9f552e97e4542de2d3cf96c9febb10c and prior reviews keep their bf63 scope; they do not approve this new head/body. No PR/draft/issue/comment/message/release or consumer acceptance was created. GCP0; no local compiler/proof execution. Remaining trust/refiner limitations are unchanged and no independent SmallSort proof credit is claimed.
