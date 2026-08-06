`onlydamage.read` pairs a column name with a number beside it and returns the
count. The exemption added this hour needs to know *which* column, so it ran the
same proximity pass again over the same bytes - a quarter of the read's cost,
and a second chance to disagree with the count it is standing next to.

`read` now carries the words it already found. The counts are `len()` of them by
construction, so the two cannot drift, and the caller stops re-deriving what it
was handed. Verdicts are identical over all 407 pages; the whole-record pass
falls from 1.06 s to 0.98 s.

While the profile was open: `look` reads each page's bytes twice, once for
itself and once inside `read`. Left alone deliberately - it is 23 ms over the
whole record and closing it means changing a signature two lanes are editing
this hour.
