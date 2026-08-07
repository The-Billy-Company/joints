The package, the CLI, and the C ABI all carried one product name and a
three-letter C floor. They now say `joints` / `jnt` / `JOINTS_`: module and
binary `joints`, library `libjnt`, header `jnt.h`, symbols `jnt_*` / `JNT_*`,
env prefix `JOINTS_` (including what used to be a separate `*_DECIDE` knob).

The old measurement verb shared the monoid's name, which would have made the
invocation a stutter. That verb is `survey` now - the same word the kernel
already uses for a walk that asks every entry state (`cursor.survey`).
`src/kernel/joint/` is untouched: that directory is the monoid the package is
named after, not a name collision to paper over.
