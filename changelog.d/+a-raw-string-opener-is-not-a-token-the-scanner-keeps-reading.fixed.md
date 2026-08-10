Swift's raw strings answer in one token instead of two, and a close now has to be as
wide as the open: `##"a "# b"##` stops being cut at the inner `"#`. The falsifier goes
from 2 missed and 4 spurious to nothing, over 4 answers it actually compared.

`eat_raw_str_part` counts the hashes, eats the quote, and then **falls through into the
body loop**, so the answer that begins at `#"` ends either just before an interpolation
or on the last hash of the close. The grammar agrees and says so by omission: there is
no opening-delimiter rule anywhere in `raw_string_literal`, only `raw_str_part`,
`raw_str_interpolation` and `raw_str_end_part`. The book had read the opener as its own
`raw_str_part`, which reported every raw string as two answers where the tree holds one,
and left the delimiter width behind, so a shorter run inside the body looked like a close.

The width is a backreference now. `"\1` is a close only at the width that opened it, so
the body walks over `"#` inside a `##` string without stopping, exactly as the C does by
counting at most `hash_count` hashes and then asking what preceded them. The resumed part
after an interpolation cannot use a backreference, because the opener is behind it, so
that probe captures the run it found and a guard holds it to the mark instead; `\###(`
inside a `#` string is not an interpolation, and the C declines it for the same reason.
