`press/` and `kernel/lex/` are sealed. Nothing outside either directory may name
a file inside it except through `press/press.zig` and `kernel/lex/scanner.zig`,
and `zoning verify` is what says so - point an import past either door and the
run fails naming the door you should have used.

The doors were published a change ago, and publishing them turned out not to be
the same as being the only way in. Four call sites still reached around: two in
`kernel/joint/reverse.zig` for `lr0` and `lalr`, one in `folio_test.zig` for
`fold`, one in `kernel/quire/quire.zig` for `inquest`. All four had a real
need - a test that isolates one stage of the table build has to be able to stop
between the stages - and no door to ask through, so they went around instead,
which is what every bypass looks like from the inside. Three more doors on
`press.zig` (`fold`, `lr0`, `lalr`) and those four are now spelled `press.fold`,
`press.lr0`, `press.lalr`, `press.inquest`. That was the whole cost of the seal:
three lines of facade and four call sites.

One wrinkle worth writing down. `src/proof.zig` names every test file in the
package by hand - that is its entire job - so a seal it has to respect is a seal
against the one file that structurally cannot. It is declared a package face
alongside `root.zig` instead: two doors, one facing out and one facing in. The
alternative was `open to proof.zig` on each seal, which says the same thing once
per seal and once more for every seal added later. The `facade` zone that used to
hold `*.zig` at the module root is gone with it, since a declared face already
stands above every zone.
