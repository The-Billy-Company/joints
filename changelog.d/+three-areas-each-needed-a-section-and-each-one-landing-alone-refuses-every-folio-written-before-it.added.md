The folio format reserves three sections it cannot read: a compiled query
program, what each repair costs, and which states a quotient merged. Named,
carried, always empty — and byte-opaque, which is the whole of the trick. The
schema digest spells every record's fields, so a section reserved as a *shape*
would break the schema the day somebody filled it; reserved as bytes, it does
not. Three areas that each need a section now cost one version bump between them
(4 → 5) instead of three, and whichever lands first fills its section without
another.

A reader that meets one of them with records in it refuses
(`FolioReservedSection`) rather than answering as though they were not there. It
has to be its own check: the version matches, the schema matches, no section
overruns or overlaps, and the seal holds — because a folio that fills a reserved
section is a *legal* folio, just one holding more than an older binary can
account for. Without the check `open` succeeds and silently drops the payload,
which is the one behaviour this format exists to refuse.
