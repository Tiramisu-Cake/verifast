# Reproduce the exact proposal

```sh
git clone https://github.com/verifast/verifast.git verifast-review
cd verifast-review
git checkout 0a83dba42db7ce0b445034ece5298afe980e57dc
git bundle verify /path/to/ready.bundle
git fetch /path/to/ready.bundle refs/heads/upstream/manuallydrop-new-final-20261009
git checkout --detach bf63b7dff2e053eea8541996d856fac4be11f6f1
git rev-parse HEAD HEAD^{tree}
./setup-build.sh
make -C src test NUMCPU=4
```

Expected tree: 687ae7dab447c94c4b87362d3d880d959c89e3de. See CHECKS.md for actual execution and skips.
No compiler/verifier commands were executed on the VPS in this preparation.
To isolate the positive reproducer after a build, run
`bin/verifast tests/rust/purely_unsafe/manuallydrop_new_cfg/forget.rs`.
The old-base focused baseline reproducer/provenance is linked in PRIOR-EVIDENCE.json;
new-base component identities and full command/resource capture are separate.
