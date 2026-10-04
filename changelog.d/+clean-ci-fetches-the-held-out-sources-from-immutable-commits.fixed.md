The parser gates read held-out sources from a contributor's warm checkout, but
CI never fetched them: the structural sweep skipped those files and the wall
gate refused to run. The press job now fetches and verifies the source corpus
before both gates. Every source URL names an immutable commit and keeps its
existing SHA256, so clean checkouts recover the same bytes as the original
measurements even when upstream branches move. A fresh fetch was verified on
2026-10-02; a warm fetch and verification required no network, and altered
upstream bytes were refused without writing files.
