# Review now; publication only after separate explicit approve

Proposed target: verifast/verifast, base branch master at
f76012fb518703b1d98e243ac4f487f16877cfcb is the tested merge base. Current master
advanced to0a83dba42db7ce0b445034ece5298afe980e57dc during this session; its clean
merge tree70478c6077d3b9d241ce7e49b8666742a227fd13 has NOT_RUN merged execution.
Fresh merged-profile CI must pass before merge acceptance. Proposed head branch:
upstream/manuallydrop-new-successors, head
da4beb61a6c2dd0e80fe4a74c5c230f3adac7cab. Head repository is a future
user-approved fork; none was created and the PR branch was not pushed.

Review the complete diff, both commits and author/committer metadata,
PR-TITLE.txt and PR-BODY.md. Approve must identify the exact head and body SHA256
from manifest (and title). This packet is not permission to publish. Substantial
later implementation/test/body changes require renewed review. Metadata/history
changes also produce a new head which must be explicitly covered by approval.

After such approval, the future publisher must:

1. Recheck upstream master and duplicate PRs read-only. If the base or patch
   changes, record the mapping and obtain applicable checks/review again.
2. Confirm the user-approved public fork/head repository and public identity.
   Create a fork or push only when that action is explicitly authorized.
3. Restore ready.bundle into a checkout with the exact prerequisite base;
   verify the bundle digest and original head/tree. No force push or rewrite
   of the published research branches. Preserve original development attribution.
4. Publish precisely the approved head to the approved repository/branch, then
   create the PR with the approved title and --body-file PR-BODY.md.
5. Record the URL/head/body and monitor actual platform CI. Do not claim the
   prepublication Linux checks establish macOS/Windows/Nix/Rocq acceptance.

No command in this document was executed to create a fork/PR/issue/comment or
contact a maintainer. A previously reported GitHub account flag is a possible
future submission obstacle. Do not test it through trial publication or bypass it;
the user resolves any required personal/account action. No legal agreement was
accepted or signed, and no fictitious identity or signoff was added.

Proposed public details: code and test files, fixture README/reproduction commands,
Git authors and committers root <root@03ohba7t.vm>, their exact dates, original
proof repository name/commit e6c02f22420ba4ff6a77e39c9610708a6096e7d7 and transplant
commit227dc163117e85d89fb1877bfc1e239a0628e5ab in the implementation commit message.
The PR body references the original repository/commit, current upstream0a83dba42db7ce0b445034ece5298afe980e57dc
and repository PR #1039 (an automatic GitHub reference). It contains no external
Cloud-report hyperlink; prior immutable evidence links remain in this review
packet only. Source tests and native commands are sufficient to reproduce it. The review
packet/Cloud infra/local paths are not in the proposed PR branch. No old archive
is recopied into the PR branch or this compact packet.
