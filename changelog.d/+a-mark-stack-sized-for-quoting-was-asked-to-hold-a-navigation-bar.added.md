html's element ancestry is a customary now - 33 rules and 14 kinds, the void
set and the `can_contain` table read straight out of `tag.h` - and it is
byte-identical to the hand it replaces: `differential run --grammar=html` is
**no differences at all** over `viewer.html`, 13,972 nodes, accepted, one root,
and `plumb` reads 72,288 built with 0 misread, 0 renamed, 0 crooked.

Two things about the algebra fell out of writing it, and neither was visible
from the seven books before it.

**An emit may name an ordinary terminal.** html declares `/>` as an anonymous
string rather than an external, so the press keeps the token it can lex and
there is no external for a rule to name - yet only the tag stack knows those two
bytes close an element. `bind` resolved every emit against the externals alone,
so the book that owed the pop could not spell the answer, and the stack kept a
tag the document had already closed: `</head>` five kilobytes later came back an
`erroneous_end_tag`. Emits now fall back to the whole terminal set, which is
what the hand-written ancestry already did for exactly this terminal.

**The mark organ was sized for quoting and is also the ancestry.** Its census
number was 8, from the deepest carried quote anyone found - kotlin's
interpolation inside a triple-quoted string inside an interpolation, which is
three. But a mark stack is what html's tag stack is, and elements do not nest
like quotes: a document that opens sixteen literals is pathological, one that
opens sixteen elements is a navigation bar. pdf.js's viewer reaches exactly
sixteen (`html > body > div ×11 > menu > button > span`), so every element from
the ninth down was silently declining to open and every close below that was
erroneous.

Widening it to `lineage.Tags`'s own 64 put `Scanner.Save` at 5,424 bytes and
tripped the ceiling that says a save fits a page - correctly, because that is
the defect the assertion was written for. So the tag bytes moved out of the
slots and into one shared LIFO arena: `marks_max * tag_max` is a product no
document pays, the deepest point of that same file spells 55 bytes of open
names, and a stack is the one shape where an arena needs no allocator, since
pushes append and pops truncate and the live bytes are always a prefix. A mark
is 4 bytes now instead of 28, 64 of them plus 192 bytes of tag room cost 872
where 8 fat ones cost 648, and `Save` is 4,080 of its 4,096.

The falsifier holds on the 54 comments a tree can name and is honest about the
rest: html's dispatch is `valid_symbols`-shaped, 22 rows turn on a `not_wanted`
the offline side has no parse table to answer, so those 1,041 answers are the
permission set's and the differential is this book's gate. The 128 tag types do
not fit a 31-kind bitset and do not have to - a kind here is the *class* a
decision reads, and a known name's member is a function of its spelling, so
identity stays in the tag and only the classes are enumerated.
