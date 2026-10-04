The reserved Rust crate now wraps the existing native bank, parser, tree,
repair, and query doors. Rust borrows enforce their destruction order, and
thread confinement prevents two workers from sharing native scratch. Each tree
retains its original source bytes, so capture predicates and byte locations
survive later parses. Strict parsing requires acceptance, one root, structural
soundness, and zero repair; diagnostic callers may explicitly retain partial
forests. Native artifacts remain a separate build selected by `JOINTS_LIB_DIR`,
with the static archive as the default and no automatic Zig build in consumer
compilation. This experimental API does not yet wrap incremental edits or prove
Python corpus coverage for Regulator.
