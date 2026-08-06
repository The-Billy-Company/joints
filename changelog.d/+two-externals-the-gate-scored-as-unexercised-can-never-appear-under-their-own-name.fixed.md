`specimen.py coverage` called an external **visible** when its name does not
start with `_`, and used that as a proxy for "a parse can name this". The proxy
has another way to fail: a grammar can `ALIAS` a symbol, which tells the parser
to emit it under a different name.

rust does it twice. `string_close` is aliased to the anonymous `"` and
`raw_string_literal_content` to `string_content`, **at every use site**, so no
parse of any input can ever name either one. tree-sitter itself reads
`fn m() { let s = "x"; }` perfectly and never says `string_close`. Those two
rows could not reach `exercised` however correct the parser was, and the gate
was scoring against a denominator that contained them.

The gate now reads the grammar's alias sites, excludes an external aliased at
every reference, and prints the name each one wears instead of hiding the
adjustment. Corpus-only, the headline moved **23 of 38 visible to 22 of 36**.

The first rule was too tight and the tier caught it before this shipped: an
alias at *one* use site is not an alias at all of them. bash aliases
`test_operator` in one production and admits it plainly in another, and the
first rule reported bash `exercised 5 of 4 visible` - a ratio above one, which
is what an over-tight rule looks like when nothing checks it. Two corrections
were needed, not one: the rule is now "aliased somewhere and referenced plainly
nowhere", and the walk that counts plain references stops descending into an
ALIAS, because counting the symbol inside an alias as its own plain reference
made every aliased external look plainly referenced and produced `0 aliased`
across all thirty grammars.

Where this goes the wrong way: the reader only understands `ALIAS` over
`SYMBOL`. `inline` and `supertypes` are two more ways a declared name can fail
to reach a tree, and neither is read yet, so 36 remains an upper bound on what
is witnessable rather than a settled count.
