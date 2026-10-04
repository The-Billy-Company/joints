The Zig package manifest now includes the customary scanner books and the C ABI
header. A repository checkout already carried both, but the published package
file list omitted them: a dependency build could not open the scanner directory,
and an installation could not copy the header. Packaging the build inputs makes
the same source buildable through either door.
