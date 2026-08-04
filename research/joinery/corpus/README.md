# The corpus - one program, eleven languages

Every rung that reports a per-language number reports it over this folder. It is
the same little ledger - push a tagged row, cache the total, invalidate the cache
on the next push, print a receipt - written once per grammar outliner imports, so
when a rank or a residue differs between two languages it differs because the
*grammar* does and not because one file happened to be longer or knottier than
the other.

| file | grammar | why it is shaped this way | its multi-line token |
|---|---|---|---|
| `ledger.c` | c | pointer declarators, a `struct` typedef, `realloc` growth | block comment, and a string spliced with a backslash |
| `ledger.cpp` | cpp | template instantiations, `std::` qualified names, `explicit` | block comment, `R"(raw string)"` |
| `ledger.go` | go | a pointer receiver, `&Ledger{}`, a two-value `:=` | block comment, backquoted raw string |
| `Ledger.java` | java | a package, generics, a boxed `Integer` as the cache | block comment, `"""` text block |
| `ledger.js` | javascript | private `#` fields, a getter, `??`, a static async method | block comment, template literal |
| `ledger.ts` | typescript | an interface, a generic type alias, arrow params, `readonly` | block comment, template literal |
| `ledger.py` | python | a `from __future__` import, PEP-604 annotations, a `@property` | `"""` docstring and banner, backslash continuation |
| `ledger.rb` | ruby | blocks, `@ivar`s, `||=` as the cache, string interpolation | `=begin` comment, `<<~` heredoc |
| `ledger.rs` | rust | `impl`, `Option` as the cache, an iterator chain, `match` | block comment, `r#"raw string"#` |
| `ledger.sh` | bash | arrays, an associative array, `[[ =~ ]]`, arithmetic `(( ))` | quoted heredoc, backslash continuation |
| `ledger.json` | json | the same ledger as *data*: nested objects, arrays, nulls | none - JSON cannot spell one |

Each file leans on the constructs its grammar is interesting for, because a
corpus of `x = 1` in eleven languages would measure nothing. They are written to
be read by a parser, not run: nothing here is built, tested, or imported by the
rest of the repo.

## The fourth column, and why I added it

For most of this build the eleven files had, between them, **zero tokens that
crossed a newline**. No block comment, no heredoc, no raw string, no text block,
no line continuation. I only noticed because a held-out sweep pressed grammars
nobody here had looked at, and css alone had 128 of them.

That is the worst kind of gap, because this package's weakness right now is
lexical. A corpus with no multi-line tokens in it cannot see the one thing that
is actually broken, so it kept reporting good news.

Widening the program to print a banner - one block comment, one multi-line
string in whatever form the language really has, a continuation where there is
one - cost **one file**: five of eleven read to the end before, four after, on
one binary measured the same minute. That file is `ledger.rs`, and it is worth
saying why rather than just counting it. Rust nests block comments, which no
regex can match, so tree-sitter-rust hands `_block_comment_content` to its
external scanner - and outliner is blind to six of rust's eleven externals. So
rust does not stumble over the comment, it never starts: stray byte at 0.

Everything else the widening exposed turned out to be cheaper. Java, JavaScript
and TypeScript died at byte 0 too when I first widened this, and that was a
regex bug rather than a scanner one; it was fixed the same night and all three
read to the end again. The honest cost of the fourth column is one language,
one reason, and it is the reason worth knowing about.

So the fourth column is a checklist, not decoration. If you add a language, its
file has to carry at least one token that spans a newline, spelled the way that
language actually spells it. Adding it as an escape inside a single-line string
does not count, which is exactly why `ledger.json` says none: JSON has no comment
and no multi-line string, so it is the honest control rather than a file I get to
fudge.

Add a language by adding one file that tells the same story, and nothing else -
a second Rust file would quietly reweight every Rust number against every other
language's one. Keep this to a single table too: `tool/rung1.py` reads the rows
above to learn which file belongs to which grammar, so a second table here
becomes eleven imaginary corpus files.
