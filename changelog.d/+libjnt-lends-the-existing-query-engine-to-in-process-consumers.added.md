`libjnt` can compile and execute tree-sitter query notation over its own parse
handles. The new query door uses the existing gloss compiler and matcher, owns
its grammar metadata and compiled source, and returns pattern indices, capture
names, and captured node references. Results are collected before publication,
so a refused predicate cannot leave a caller with half a successful answer.
Unsupported branches the matcher declines are refused at the boundary as well.
Malformed queries and execution failures use the existing status and error
channel; a query executed on another parser's tree is explicitly refused.

Foreign predicates have an explicit refuse/admit/deny policy, while implemented
text predicates run against the original source bytes. Queries borrow their
parser identity, and results borrow their query and tree; the header states
when each handle and source buffer may be released.

The tree door also exposes the parser's authoritative scar list: deletion
spans and supplied terminals, with the refusal's context. This gives partial-file
consumers repair provenance without manufacturing error nodes, and lets strict
consumers refuse a repaired tree even when it eventually accepts and is sound.

These are additive symbols and keep the existing C ABI compatibility integer.
Tests compile queries against the committed JSON grammar through both pressed
and mapped parser paths and cover captures, text predicates, empty results,
malformed queries, source ownership, parser identity, predicate refusal, and
repair spans.
