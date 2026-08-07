`.github/workflows/release.yml` - a `v*` tag builds the Python package, proves
the tag names the version the metadata declares, installs the wheel on a clean
interpreter and imports it, then publishes to PyPI through Trusted Publishing.
No API token exists to rotate or leak; the upload credential is an OIDC token
minted for one run and scoped to one environment.

The upload is probed first and is idempotent. A published version is immutable
on PyPI, so "already present" is success rather than a collision - and a
registry that fails to answer is never read as "absent", because that is the
reading that publishes twice.

Deliberately smaller than the sibling packages' release contract, which gates
version parity across every mirror, changelog quality, CI-green and
tag-ancestor, a wheel matrix and a cross-ABI smoke, and runs a parallel
crates.io leg. None of that is load-bearing while the wheel is pure metadata:
`0.0.0` exports nothing, bundles no native library, and is `py3-none-any`.
Gates written to guard an artifact that does not exist yet are ceremony no real
release has ever exercised, which is the kind that fails the first time it
matters. They arrive with the first version that ships a binding.

One-time setup this cannot do for itself: PyPI needs a trusted publisher for
the `joints` project pointing at this repository, workflow `release.yml`,
environment `pypi`. Until the project exists that is a "pending" publisher,
which does not reserve the name and is invalidated if somebody registers
`joints` first - the name is only held once this workflow has actually run.
