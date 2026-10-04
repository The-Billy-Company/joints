# Publisher identity and recovery

The `../publisher.py` entry point keeps current workflow authorization separate
from the original release source. `context.py` resolves signed annotated tags
and validates the original release run, required build and installed checks,
artifact inventory, repository IDs, source commit, and archive digests.
`controls.py` and `artifact_controls.py` exercise refusals offline, including the
immutable OIDC subject format this repository uses. Run
`python3 -O tool/publisher.py --selftest`.

An empty dispatch from main builds without registry credentials or writes.
Recovery takes both `release_tag` and `artifact_run`, checks CI for both
the original source and current automation, and reuses the original artifacts.
Before registry or GitHub writes, `assert-context` resolves the signed tag and
original run again. Source checkouts stay at the tag commit; the readiness
helper runs from the separately checked out current automation commit.

`artifacts.py` verifies all original ZIP bytes against authenticated API digests
and compares their source ledgers to the clean tag checkout. It follows GitHub's
signed storage redirect with a fresh request carrying no GitHub authorization.
The following command also compares local portable packages to those verified
ZIP members:

```bash
python3 control/tool/publisher.py verify-artifacts --release-tag "$TAG" \
  --source-sha "$SOURCE_SHA" --artifact-run "$ARTIFACT_RUN" \
  --artifact-root dist --source-root joints
```

Run recovery from main. Use
`--native-target linux-x86_64`, `macos-arm64`, or `all` for the corresponding local
native archives. It rejects unsafe ZIP paths, links, duplicates, unexpected
members and changed payloads; the optional final `SHA256SUMS` must be derived
exactly from the authenticated payloads.

PyPI readiness validates all four source version mirrors and the clean source
checkout, then checks the current workflow's immutable owner/repository IDs,
subject, ref, commit, workflow path, environment, audience, issuer, and timing.
It exchanges and immediately burns a temporary credential without uploading a
version or persisting credentials. PyPI may create a project from its pending
publisher during that exchange, so crates readiness runs first. Each absent
registry version must pass readiness before either package is uploaded.
Existing versions with identical verified bytes may skip readiness and upload.
