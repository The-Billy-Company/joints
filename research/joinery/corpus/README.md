# The corpus - one program, eleven languages

Every rung that reports a per-language number reports it over this folder. It is
the same little ledger - push a tagged row, cache the total, invalidate the cache
on the next push - written once per grammar outliner imports, so when a rank or a
residue differs between two languages it differs because the *grammar* does and
not because one file happened to be longer or knottier than the other.

| file | grammar | why it is shaped this way |
|---|---|---|
| `ledger.c` | c | pointer declarators, a `struct` typedef, `realloc` growth |
| `ledger.cpp` | cpp | template instantiations, `std::` qualified names, `explicit` |
| `ledger.go` | go | a pointer receiver, `&Ledger{}`, a two-value `:=` |
| `Ledger.java` | java | a package, generics, a boxed `Integer` as the cache |
| `ledger.js` | javascript | private `#` fields, a getter, `??`, a static async method |
| `ledger.ts` | typescript | an interface, a generic type alias, arrow params, `readonly` |
| `ledger.py` | python | a `from __future__` import, PEP-604 annotations, a `@property` |
| `ledger.rb` | ruby | blocks, `@ivar`s, `||=` as the cache, string interpolation |
| `ledger.rs` | rust | `impl`, `Option` as the cache, an iterator chain, `match` |
| `ledger.sh` | bash | arrays, an associative array, `[[ =~ ]]`, arithmetic `(( ))` |
| `ledger.json` | json | the same ledger as *data*: nested objects, arrays, nulls |

Each file leans on the constructs its grammar is interesting for, because a
corpus of `x = 1` in eleven languages would measure nothing. They are written to
be read by a parser, not run: nothing here is built, tested, or imported by the
rest of the repo.

Add a language by adding one file that tells the same story, and nothing else -
a second Rust file would quietly reweight every Rust number against every other
language's one.
