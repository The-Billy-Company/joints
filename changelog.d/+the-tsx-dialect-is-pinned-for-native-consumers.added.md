TSX consumers need their own grammar rather than a TypeScript parse of JSX. The
manifest now pins TSX at the same repository commit as TypeScript, including its
scanner shim and the shared scanner header. Fetch and verification cover the
consumer pin without changing the dossier or held-out measurement corpora. The
grammar and companions were fetched from that immutable commit and checked
against their recorded SHA256 hashes on 2026-10-02.
